# Gettext Generation Workbench

Versão de desenvolvimento **0.1.0**, da [Lofrano Tecnologia](https://lofranotecnologia.com.br).
Gem Ruby e CLI originais para exercitar extração, atualização, compilação MO e renderização traduzida real, sem rede durante o uso. Os catálogos são sintéticos. Não é uma avaliação de qualidade das traduções nem um sistema de implantação.

## Preparação, instalação e testes

Ambiente Linux qualificado: Ruby **3.4.12** em `/usr/local/bin/ruby`, Bundler **2.6.9**, RubyGettext **3.5.2**, GNU `msgfmt`, `msgmerge`, `msgunfmt`, `msgattrib` **0.21**, Python **3.11.2** em `/usr/bin/python3`. Outras versões são rejeitadas deliberadamente. Nenhum pacote é instalado dinamicamente durante o uso.

No ambiente Debian/Ruby qualificado:

```sh
apt-get update
apt-get install -y --no-install-recommends gettext python3
gem install bundler --version 2.6.9 --no-document
BUNDLE_FROZEN=true bundle install
bundle exec ruby test/run.rb
bundle exec ruby bin/catalog_workbench demo --assert
```

A preparação exige permissões adequadas para instalar pacotes. Depois disso, testes e demonstração são offline. O `Gemfile.lock` incluído foi resolvido com Bundler e registra os checksums oficiais; a instalação congelada mantém esse conjunto qualificado. O arquivo oficial da gem gettext 3.5.2 tem SHA-256 `ada02c59aa7e9f56bd2522faedaed16421dd2f3ddb5fe28628c0be5abcbf3c74`.

Para instalar a gem com seus workers, helper e fixtures:

```sh
gem build gettext-generation-workbench.gemspec --output /tmp/workbench.gem
gem install --local /tmp/workbench.gem --ignore-dependencies --no-document
catalog_workbench demo --assert
```

`--ignore-dependencies` pressupõe a preparação anterior. Os recursos pertencentes ao pacote são encontrados por `__dir__`, não pelo diretório atual.

## Demonstração offline

Prefixo esperado da saída legível:

```text
Gettext Generation Workbench development 0.1.0
pt_BR: 0 arquivos | 1 arquivo | 2 arquivos
contexts: Abrir / Aberto
merge: 3 active, 1 obsolete
fuzzy: Run
UTF-8: Ação (4 code points, 6 bytes)
pinning: 4 old readers; new reader: Abrir novamente
deterministic: true
```

A última linha é JSON canônico com hashes reais, resultados dos renderizadores, contagens independentes do MO, evidências da atualização, fixação de gerações e preservação após falha. Não inclui relógio, PID nem nome temporário. `--assert` retorna falha se as expectativas fixas divergirem. As asserções confrontam essas expectativas com as ferramentas GNU reais e o runtime RubyGettext qualificado.

O catálogo principal tem três mensagens ativas: `verb/Open`, `state/Open` e o plural de arquivos. A revisão remove `state/Open` e inclui `Settings`. Os exemplos fuzzy `Run` e Unicode `Action` ficam separados para não alterar essa contagem.

## Uso

```sh
bundle exec ruby bin/catalog_workbench extract fixtures/source_v1.rb
bundle exec ruby bin/catalog_workbench compile /tmp/meu-catalogo fixtures/source_v1.rb en=fixtures/en.po pt_BR=fixtures/pt_BR.po
bundle exec ruby bin/catalog_workbench render /tmp/meu-catalogo pt_BR
bundle exec ruby bin/catalog_workbench inspect /tmp/meu-catalogo pt_BR
```

Escolha um diretório novo ou um armazenamento privado já marcado pelo workbench. `extract` imprime POT normalizado. `merge LOCALE CATALOG.po TEMPLATE.pot` imprime JSON com PO normalizado, evidência bruta do GNU msgmerge e contagens. Compilação, renderização e inspeção também imprimem JSON. Erros públicos contêm somente códigos, em JSON no stderr, com status 2; não expõem texto nativo, caminhos ou conteúdo dos catálogos.

API Ruby:

```ruby
require "gettext_generation_workbench"
wb = GettextGenerationWorkbench::Workbench.new("/tmp/catalogo-ruby")
pot = wb.extract(source: File.read("fixtures/source_v2.rb", encoding: "UTF-8"))
resultado = wb.merge(catalog: File.read("fixtures/pt_BR.po", encoding: "UTF-8"),
                     template: pot, locale: "pt_BR")
wb.compileGeneration(source: File.read("fixtures/source_v2.rb", encoding: "UTF-8"),
                     catalogs: { "pt_BR" => resultado.fetch("po") })
puts wb.renderFixture(locale: "pt_BR").fetch("verb") # Abrir
```

A extração usa somente o parser Ruby mantido pelo RubyGettext. A fonte é dado confiável para extração: nunca é importada ou executada. O renderizador é código fixo deste pacote, não código fornecido pelo chamador.

## Decisões e limitações

Um lock cooperativo de escrita cobre a compilação inteira e a troca atômica do ponteiro ativo. Cada geração é identificada pelo hash do manifesto e contém arquivos somente para leitura. O renderizador lê o ponteiro uma vez, copia e verifica seu MO em uma árvore privada imutável e não consulta mais o ponteiro. Cada contexto de locale tem um processo separado; não se pressupõe que o estado global do RubyGettext seja local à thread.

Antes de qualquer bind ou consulta de plural, o worker abre o MO com o parser mantido e valida seu cabeçalho bruto. Somente o literal exato `nplurals=2; plural=(n != 1);` é aceito. O RubyGettext 3.5.2 posteriormente avalia internamente essa expressão fixa; o aplicativo não avalia expressões arbitrárias do catálogo. Não há suporte geral às expressões de plural GNU. O exemplo português usa a regra fornecida, com plural para zero, sem generalização para todos os locales portugueses.

Por operação: até 16 catálogos e 16 MiB agregados de entrada. Por instância: quatro renderizadores simultâneos; o quinto é rejeitado antes de iniciar processo. Cada filho supervisionado tem prazo monotônico de cinco segundos e captura combinada de stdout/stderr de 64 KiB. Há limites adicionais de entradas, strings e manifesto. Não são cotas globais, de disco ou de memória antes do parser.

GNU valida sintaxe e formatos printf marcados. Fuzzy é tratado como não traduzido. Obsoletos permanecem na evidência PO, mas não contam como ativos nem aparecem no runtime. Não há promessa de completude ou correção linguística. Não há plugins arbitrários, telemetria, serviços remotos ou dependência de modelo/API.

O helper Linux mantém o filho direto sem reap até enviar TERM/KILL e selar permanentemente os sinais; só então coleta o líder e descendentes adotados. Os filhos fixos confiáveis não escapam da sessão. Isso não é um sandbox geral nem uma garantia para I/O ininterruptível do kernel. O armazenamento pressupõe filesystem local privado e escritores cooperativos; hashes e permissões não autenticam contra outro processo hostil do mesmo usuário. As gerações acumulam; não existe limpeza automática.

## Contêiner

```sh
docker build -t gettext-workbench:dev .
docker run --rm --network=none --read-only --cap-drop=ALL --tmpfs /tmp:rw,nosuid,nodev,size=128m gettext-workbench:dev
```

O Dockerfile fixa o digest da base Ruby. Repositórios apt e dependências transitivas resolvidas continuam sendo entradas da construção; não se promete uma imagem de SO idêntica bit a bit. O comando final executa diretamente a gem instalada, como usuário não root, sem instalação na inicialização.

Consulte [contrato](docs/contract.md), [projeto](docs/design.md), [contribuição](CONTRIBUTING.md) e [segurança](SECURITY.md). Código do projeto: MIT, copyright 2026 Lofrano Tecnologia. As licenças Ruby/LGPL do RubyGettext e GPL das ferramentas GNU permanecem separadas; não são relicenciadas como MIT. Fontes: [RubyGettext](https://github.com/ruby/gettext), [GNU gettext](https://www.gnu.org/software/gettext/manual/gettext.html), [Encoding do Ruby](https://docs.ruby-lang.org/en/3.4/Encoding.html).


O `Gemfile.lock` incluído foi resolvido de fato com Bundler e registra checksums das gems. A preparação congelada usa esse conjunto qualificado. O helper restaura SIGCHLD ao padrão antes de criar o filho, evitando o descarte automático herdado; sinais TERM/KILL precedem o selo e o recolhimento. A limpeza abre permissão de diretório somente nas cópias temporárias já encerradas e conserva as gerações publicadas somente leitura. Arquivo de trava não regular ou simbólico é rejeitado; isso não amplia o contrato para um sistema de arquivos hostil.
