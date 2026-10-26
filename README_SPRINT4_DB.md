# SuperNova Vet – Sprint 4 – Mastering Relational and Non-Relational Database

## Arquivos
| Arquivo | O que é | Entregável (pontos) |
|---|---|---|
| `SuperNovaVET_SP4.sql` | Tabelas, packages, triggers, inserts e testes (Oracle) | 2 – Empacotamento (25) |
| `exportar_json.sql` | Gera `supernova_vet.json` a partir do Oracle | 3 – JSON (20) |
| `supernova_vet.json` | Exemplo do JSON esperado (**regenere pelo Oracle** antes de entregar) | 3 |
| `mongo_supernova.js` | Cria a coleção, importa o JSON e faz consultas (mongosh) | 4 – MongoDB (25) |
| `java/` | Repository + Controller que chamam as procedures | integração (vídeo) |
| Modelos lógico/físico (PDF) | Do Data Modeler, **corrigidos conforme o feedback da Sprint 3** | 1 – (20) |
| Vídeo | Roteiro abaixo | 5 – (10) |

## Passo a passo
1. **Oracle:** rode `SuperNovaVET_SP4.sql` num schema limpo (ou descomente a seção 0 para refazer). Confira que não ficou nenhum objeto INVALID:
   `SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';`
2. **JSON:** rode `exportar_json.sql` no SQL*Plus/SQLcl (ou `EXEC pkg_pet_json.pr_exportar_dataset_json;` no SQL Developer e copie a saída para `supernova_vet.json`). Valide em jsonlint.com.
3. **MongoDB:** com o JSON na mesma pasta: `mongosh "mongodb://localhost:27017" --file mongo_supernova.js`
4. **Java:** copie os dois arquivos de `java/` para o seu projeto Spring Boot da Sprint 3 (ajuste `package` e imports) e suba a API apontando para o mesmo Oracle.

## Mapa dos packages
| Package | Conteúdo |
|---|---|
| `pkg_log` | `pr_registrar_erro` (autonomous transaction) |
| `pkg_pet_regras` | `fn_classificar_risco_por_idade` + constantes das faixas |
| `pkg_pet_json` | `fn_montar_json_pet`, `pr_listar_pets_tutores_json`, `fn_exportar_dataset_json`, `pr_exportar_dataset_json` |
| `pkg_pet_relatorio` | `pr_relatorio_peso_tutor_especie` |
| `pkg_pet_auditoria` | `fn_formatar_pet`, `pr_registrar` |
| `pkg_pet_app` | `pr_inserir_tutor`, `pr_inserir_pet`, `pr_registrar_vacina`, `pr_atualizar_peso_pet`, `pr_excluir_pet`, `pr_listar_pets` |
| Triggers (fora de package) | `trg_definir_risco_pet` e `trg_auditoria_pet` – só chamam os packages |

## Roteiro do vídeo (todos os integrantes falando, com narração)
1. **Modelo** (30s): mostrar o modelo lógico/físico e dizer o que foi corrigido.
2. **Oracle** (2 min): rodar o script; mostrar os packages no SQL Developer (árvore *Packages*) e os INSERTs nas tabelas.
3. **Procedures no backend** (3 min): com a API Java no ar, chamar no Postman/Insomnia:
   `POST /api/procedures/pets`, `POST .../vacinas`, `PUT .../peso`, `GET /api/procedures/pets`.
   Depois mostrar no Oracle o `SELECT` das tabelas e de `ch_pet_auditoria` (trigger).
   Mostrar também um erro tratado: `POST /api/procedures/pets?...&idTutor=999` → 400 com `ORA-20003`.
4. **JSON** (1 min): rodar `exportar_json.sql` e abrir o `supernova_vet.json`.
5. **MongoDB** (2 min): rodar `mongo_supernova.js` e mostrar a coleção `pets` no Compass/mongosh + as consultas.

## Checklist de penalidades
- [ ] Nomes de arquivos no padrão pedido pelo professor (arquivo fora do padrão: −10)
- [ ] Vídeo com narração (sem narração: −5)
- [ ] Nenhum erro na execução do script (execução com erro = sem avaliação)
- [ ] PDF do modelo lógico/físico + SQL da Sprint 3 corrigido conforme feedback
