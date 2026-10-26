// =====================================================================
// SuperNova Vet - Sprint 4 - MongoDB (mongosh)
// Cria o banco/colecao, importa o supernova_vet.json (gerado pelo Oracle)
// e roda consultas de exemplo.
//
// Como rodar (na pasta onde esta o supernova_vet.json):
//   mongosh "mongodb://localhost:27017" --file mongo_supernova.js
//   (Atlas: mongosh "mongodb+srv://usuario:senha@cluster.mongodb.net" --file mongo_supernova.js)
//
// MODELAGEM: 1 colecao "pets", 1 documento por pet.
// O tutor, vacinas, consultas, medicamentos e lembretes ficam EMBUTIDOS
// no documento do pet (sao sempre lidos junto com o pet e nao existem
// sem ele) - isso evita os JOINs do modelo relacional.
// =====================================================================

const fs = require('fs');

const NOME_BANCO   = 'supernova_vet';
const ARQUIVO_JSON = 'supernova_vet.json';

const banco = db.getSiblingDB(NOME_BANCO);

// ---------------------------------------------------------------
// 1) Recria a colecao com validacao de schema ($jsonSchema)
// ---------------------------------------------------------------
banco.pets.drop();

banco.createCollection('pets', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['id_pet', 'nm_pet', 'ds_especie', 'tutor'],
      properties: {
        id_pet:         { bsonType: 'number', description: 'id do pet no Oracle' },
        nm_pet:         { bsonType: 'string' },
        ds_especie:     { bsonType: 'string' },
        ds_raca:        { bsonType: ['string', 'null'] },
        nr_idade:       { bsonType: ['number', 'null'], minimum: 0 },
        nr_peso:        { bsonType: ['number', 'null'], minimum: 0 },
        ds_sexo:        { bsonType: ['string', 'null'] },
        ds_nivel_risco: { bsonType: 'string' },
        tutor: {
          bsonType: 'object',
          required: ['id_tutor', 'nm_tutor', 'ds_email'],
          properties: {
            id_tutor:    { bsonType: 'number' },
            nm_tutor:    { bsonType: 'string' },
            ds_email:    { bsonType: 'string' },
            nr_telefone: { bsonType: ['string', 'null'] }
          }
        },
        vacinas: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['nm_vacina', 'dt_aplicacao'],
            properties: {
              nm_vacina:       { bsonType: 'string' },
              dt_aplicacao:    { bsonType: 'date' },
              dt_proxima_dose: { bsonType: ['date', 'null'] }
            }
          }
        },
        consultas:    { bsonType: 'array' },
        medicamentos: { bsonType: 'array' },
        lembretes:    { bsonType: 'array' }
      }
    }
  }
});

// ---------------------------------------------------------------
// 2) Importa o JSON (o Oracle exporta datas como texto "AAAA-MM-DD";
//    aqui viram Date de verdade antes de gravar)
// ---------------------------------------------------------------
function paraData(texto) {
  return texto ? new Date(texto + 'T00:00:00Z') : null;
}

function converterDatas(doc) {
  (doc.vacinas || []).forEach(v => {
    v.dt_aplicacao    = paraData(v.dt_aplicacao);
    v.dt_proxima_dose = paraData(v.dt_proxima_dose);
  });
  (doc.consultas || []).forEach(c => {
    c.dt_consulta = paraData(c.dt_consulta);
  });
  (doc.medicamentos || []).forEach(m => {
    m.dt_inicio = paraData(m.dt_inicio);
    m.dt_fim    = paraData(m.dt_fim);
  });
  (doc.lembretes || []).forEach(l => {
    l.dt_lembrete = paraData(l.dt_lembrete);
  });
  return doc;
}

const documentos = JSON.parse(fs.readFileSync(ARQUIVO_JSON, 'utf8')).map(converterDatas);
const resultado  = banco.pets.insertMany(documentos);
print('Documentos importados: ' + Object.keys(resultado.insertedIds).length);

// ---------------------------------------------------------------
// 3) Indices
// ---------------------------------------------------------------
banco.pets.createIndex({ id_pet: 1 }, { unique: true });
banco.pets.createIndex({ 'tutor.ds_email': 1 });
banco.pets.createIndex({ ds_nivel_risco: 1 });
banco.pets.createIndex({ 'vacinas.dt_proxima_dose': 1 });

// ---------------------------------------------------------------
// 4) Consultas de exemplo (para mostrar no video)
// ---------------------------------------------------------------
print('\n--- 4.1) Todos os pets (so nome, especie e risco) ---');
printjson(banco.pets.find({}, { _id: 0, nm_pet: 1, ds_especie: 1, ds_nivel_risco: 1 }).toArray());

print('\n--- 4.2) Pets com risco ALTO e o tutor ---');
printjson(banco.pets.find({ ds_nivel_risco: 'ALTO' }, { _id: 0, nm_pet: 1, 'tutor.nm_tutor': 1 }).toArray());

print('\n--- 4.3) Pets com vacina vencendo ate 31/03/2027 ---');
printjson(banco.pets.find(
  { 'vacinas.dt_proxima_dose': { $lte: new Date('2027-03-31T00:00:00Z') } },
  { _id: 0, nm_pet: 1, 'vacinas.nm_vacina': 1, 'vacinas.dt_proxima_dose': 1 }
).toArray());

print('\n--- 4.4) Peso medio e quantidade por especie ---');
printjson(banco.pets.aggregate([
  { $group: { _id: '$ds_especie', qtd_pets: { $sum: 1 }, peso_medio: { $avg: '$nr_peso' } } },
  { $sort: { _id: 1 } }
]).toArray());

print('\n--- 4.5) Lembretes pendentes (por pet) ---');
printjson(banco.pets.aggregate([
  { $unwind: '$lembretes' },
  { $match: { 'lembretes.ds_status': 'PENDENTE' } },
  { $project: { _id: 0, nm_pet: 1, mensagem: '$lembretes.ds_mensagem', data: '$lembretes.dt_lembrete' } },
  { $sort: { data: 1 } }
]).toArray());

// ---------------------------------------------------------------
// ALTERNATIVA ao passo 2 (se o require('fs') nao funcionar no seu mongosh):
//   mongoimport --uri "mongodb://localhost:27017" --db supernova_vet \
//     --collection pets --file supernova_vet.json --jsonArray
//   (a colecao nao pode ter o validator de datas nesse caso: remova o bloco 1
//    antes ou deixe so o drop/create sem validator e converta as datas
//    depois com um forEach usando converterDatas + replaceOne)
// ---------------------------------------------------------------
