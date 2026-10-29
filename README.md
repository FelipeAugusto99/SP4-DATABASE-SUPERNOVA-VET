# SuperNova Vet – Sprint 4 – Mastering Relational and Non-Relational Database

Challenge 2026 – FIAP – Análise e Desenvolvimento de Sistemas (2TDSPG)

## Integrantes
| RM | Nome |
|---|---|
| 563982 | Felipe Augusto Lopes Ferreira |
| 565802 | Kaique Mascarenhas dos Santos |

## Vídeo de demonstração
**Link:** <COLE_AQUI_O_LINK_DO_YOUTUBE>

## Aplicação Java (backend)
A API que chama as procedures usa o mesmo banco Oracle (tabelas `ch_*`).
**Repositório da API:** https://github.com/FelipeAugusto99/SP4-SUPERNOVAVET-API
As classes que chamam as procedures estão no repositório da API: `src/main/java/Novamonitor/repository/PetProcedureRepository.java` e `src/main/java/Novamonitor/controller/PetProcedureController.java` (regra de segurança em `security/SecurityConfig.java`).

## Visão geral
O SuperNova Vet monitora a saúde preventiva de pets. Nesta sprint o banco relacional Oracle foi empacotado em PL/SQL, usado por uma API Java (Spring Boot) por meio de procedures, exportado para JSON e importado no MongoDB como uma coleção de documentos.

## Arquivos
| Arquivo | Conteúdo |
|---|---|
| `2TDSPG_2026_Proj_BD.pdf` | Modelos lógico e físico, prints de execução e exceções tratadas (entregue em arquivo separado no portal) |
| `2TDSPG_2026_CodigoSql_Integrantes.sql` | Tabelas, packages, triggers, inserts (5 por tabela) e testes (Oracle) |
| `exportar_json.sql` | Exporta o dataset do Oracle para `supernova_vet.json` |
| `supernova_vet.json` | Dataset gerado pelo Oracle (1 documento por pet) |
| `mongo_supernova.js` | Criação da coleção, importação e consultas (mongosh) |
| `mongo_compass.js` | Mesma lógica de consultas, para colar no painel MONGOSH do Compass |

## Packages (PL/SQL)
| Package | Conteúdo |
|---|---|
| `pkg_log` | `pr_registrar_erro` (autonomous transaction) |
| `pkg_pet_regras` | `fn_classificar_risco_por_idade` |
| `pkg_pet_json` | `fn_montar_json_pet`, `pr_listar_pets_tutores_json`, `fn_exportar_dataset_json`, `pr_exportar_dataset_json` |
| `pkg_pet_relatorio` | `pr_relatorio_peso_tutor_especie` (soma, subtotal e total geral manuais) |
| `pkg_pet_auditoria` | `fn_formatar_pet`, `pr_registrar` |
| `pkg_pet_app` | `pr_inserir_tutor`, `pr_inserir_pet`, `pr_registrar_vacina`, `pr_atualizar_peso_pet`, `pr_excluir_pet`, `pr_listar_pets` |

Triggers (fora de package, apenas chamam os packages): `trg_definir_risco_pet` e `trg_auditoria_pet`.

Todas as rotinas tratam exceções (`RAISE_APPLICATION_ERROR` -20001 a -20006) e registram erros inesperados em `ch_log_erro`.

## Como executar
1. **Oracle:** rode `2TDSPG_2026_CodigoSql_Integrantes.sql` inteiro (F5 no SQL Developer) em um schema limpo. A seção 0 (DROPs) vem comentada; para refazer tudo, descomente-a.
2. **JSON:** rode `EXEC pkg_pet_json.pr_exportar_dataset_json;` (ou `exportar_json.sql` no SQL*Plus) e salve a saída como `supernova_vet.json`.
3. **MongoDB:**
   - Com `mongosh`: `mongosh "mongodb://localhost:27017" --file mongo_supernova.js` (na pasta do JSON).
   - Com o Compass: banco `supernova_vet`, coleção `pets` → *Import data* → `supernova_vet.json`; depois cole `mongo_compass.js` no painel MONGOSH.
4. **API Java:** clone o repositório da API, configure as credenciais do Oracle por variáveis de ambiente (`DB_USERNAME` e `DB_PASSWORD`) e suba com `./mvnw spring-boot:run`. As procedures ficam em `/procedures/**` (perfis ADMIN e VETERINARIO), documentadas no Swagger (`/swagger-ui/index.html`).

## Modelagem no MongoDB
Uma coleção `pets`, um documento por pet. Tutor, vacinas, consultas, medicamentos e lembretes ficam **embutidos** no documento, pois são sempre lidos junto com o pet e não existem sem ele. Há validação `$jsonSchema`, datas convertidas para `Date` e índices em `id_pet`, `tutor.ds_email`, `ds_nivel_risco` e `vacinas.dt_proxima_dose`.