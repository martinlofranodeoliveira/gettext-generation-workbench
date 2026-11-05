module GettextGenerationWorkbench
  class Store
    MARKER = "gettext-generation-workbench store 0.1.0\n"
    JOB_MARKER = "gettext-generation-workbench job 0.1.0\n"
    attr_reader :root

    def initialize(root)
      GettextGenerationWorkbench.safe("E_STORE") do
        @root = File.expand_path(root)
        Dir.mkdir(@root, 0o700) unless File.exist?(@root)
        GettextGenerationWorkbench.fail!("E_STORE") if File.symlink?(@root) || !File.directory?(@root)
        marker = File.join(@root, ".workbench-store")
        if File.exist?(marker)
          GettextGenerationWorkbench.fail!("E_STORE") unless GettextGenerationWorkbench.read(marker, 128) == MARKER
        else
          GettextGenerationWorkbench.fail!("E_STORE") unless Dir.children(@root).empty?
          File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(MARKER) }
        end
        %w[jobs generations].each do |name|
          path = File.join(@root, name)
          Dir.mkdir(path, 0o700) unless File.exist?(path)
          GettextGenerationWorkbench.fail!("E_STORE") if File.symlink?(path) || !File.directory?(path)
        end
      end
    end

    def new_job
      path = Dir.mktmpdir("job-", File.join(root, "jobs"))
      File.write(File.join(path, ".job"), JOB_MARKER)
      path
    end

    def cleanup(job)
      return unless job && File.directory?(job)
      expected_parent = File.join(root, "jobs")
      GettextGenerationWorkbench.fail!("E_STORE") unless !File.symlink?(job) && File.dirname(job) == expected_parent &&
        File.basename(job).start_with?("job-") &&
        GettextGenerationWorkbench.read(File.join(job, ".job"), 128) == JOB_MARKER
      # Only this invocation's marked, private temporary directory is removed.
      # Renderer snapshots are read-only while the child runs. It has been
      # reaped before cleanup; reopen only these owned job directories so their
      # entries can be unlinked by an unprivileged caller.
      stack = [job]
      until stack.empty?
        directory = stack.pop
        next if File.symlink?(directory) || !File.directory?(directory)
        File.chmod(0o700, directory)
        Dir.children(directory).each { |name| stack << File.join(directory, name) }
      end
      FileUtils.remove_entry_secure(job)
    end

    def job
      path = new_job
      yield path
    ensure
      cleanup(path)
    end

    def writer
      path = File.join(root, "writer.lock")
      GettextGenerationWorkbench.fail!("E_STORE") if File.symlink?(path)
      # NONBLOCK prevents a preexisting FIFO from hanging before validation;
      # NOFOLLOW and fstat bind the regular-file check to the opened descriptor.
      flags = File::RDWR | File::CREAT | File::NONBLOCK | File::NOFOLLOW
      File.open(path, flags, 0o600) do |f|
        GettextGenerationWorkbench.fail!("E_STORE") unless f.stat.file?
        f.flock(File::LOCK_EX)
        yield
      ensure
        f.flock(File::LOCK_UN)
      end
    end

    def active
      path = File.join(root, "active.json")
      GettextGenerationWorkbench.fail!("E_NO_GENERATION") unless File.exist?(path)
      pointer = JSON.parse(GettextGenerationWorkbench.read(path, 4096))
      GettextGenerationWorkbench.fail!("E_MANIFEST") unless pointer.keys.sort == %w[generation id] &&
        pointer["generation"].is_a?(Integer) && pointer["generation"].positive? &&
        pointer["id"].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(pointer["id"])
      directory = File.join(root, "generations", pointer.fetch("id"))
      bytes = GettextGenerationWorkbench.read(File.join(directory, "manifest.json"), MANIFEST_LIMIT)
      GettextGenerationWorkbench.fail!("E_INTEGRITY") unless GettextGenerationWorkbench.sha(bytes) == pointer["id"]
      manifest = JSON.parse(bytes)
      GettextGenerationWorkbench.fail!("E_MANIFEST") unless manifest["format"] == 1 &&
        manifest["catalogs"].is_a?(Hash) && manifest["catalogs"].size.between?(1, 16)
      [pointer, manifest, directory]
    end

    def publish(payload, manifest, job)
      bytes = GettextGenerationWorkbench.canonical(manifest)
      GettextGenerationWorkbench.fail!("E_MANIFEST") if bytes.bytesize > MANIFEST_LIMIT
      id = GettextGenerationWorkbench.sha(bytes)
      File.write(File.join(payload, "manifest.json"), bytes)
      File.write(File.join(payload, ".generation"), "gettext-generation-workbench generation 0.1.0\n")
      Dir.glob(File.join(payload, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next if %w[. ..].include?(File.basename(path))
        if File.file?(path)
          File.open(path, "rb") { |f| f.fsync }
          File.chmod(0o400, path)
        end
      end
      destination = File.join(root, "generations", id)
      # Content-addressed directories are never edited or garbage-collected.
      unless File.exist?(destination)
        File.rename(payload, destination)
        seal_directories(destination)
      end
      previous = File.exist?(File.join(root, "active.json")) ? active.first.fetch("generation") : 0
      pointer = { "generation" => previous + 1, "id" => id }
      temporary = File.join(job, "active.next")
      File.open(temporary, "wb", 0o600) do |f|
        f.write(GettextGenerationWorkbench.canonical(pointer))
        f.flush
        f.fsync
      end
      File.open(File.join(root, "generations"), "rb") { |f| f.fsync }
      File.rename(temporary, File.join(root, "active.json"))
      File.open(root, "rb") { |f| f.fsync }
      pointer.merge("manifest" => manifest)
    end

    def seal_directories(directory)
      Dir.children(directory).each do |name|
        path = File.join(directory, name)
        seal_directories(path) if File.directory?(path)
      end
      File.open(directory, "rb") { |f| f.fsync }
      File.chmod(0o500, directory)
    end
  end
end
