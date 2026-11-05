FROM ruby:3.4-bookworm@sha256:8853c6f24866429483fce3a869e61a6a13916beb2720468c6d95c78f41c0f564
RUN apt-get update && apt-get install -y --no-install-recommends gettext python3
WORKDIR /opt/workbench
COPY . .
RUN gem install bundler --version 2.6.9 --no-document && BUNDLE_FROZEN=true bundle install --jobs 2 --retry 0 && gem build gettext-generation-workbench.gemspec --output /tmp/workbench.gem && gem install --local /tmp/workbench.gem --ignore-dependencies --no-document
ENV HOME=/tmp
USER 10001:10001
WORKDIR /tmp
CMD ["catalog_workbench", "demo", "--assert"]
