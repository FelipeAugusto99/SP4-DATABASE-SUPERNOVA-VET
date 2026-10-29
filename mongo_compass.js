// =====================================================================
// SuperNova Vet - Sprint 4 - MongoDB - versao para o COMPASS
// Use depois de importar o supernova_vet.json pela interface do Compass
// (banco: supernova_vet / colecao: pets). Cole TUDO no painel >_MONGOSH.
// O que faz: converte as datas (texto -> Date), cria a validacao de schema,
// cria os indices e roda as consultas de exemplo.
// Pode colar mais de uma vez (nao duplica nada).
// =====================================================================
(function () {
  const banco  = db.getSiblingDB('supernova_vet');
  const mostrar = obj => console.log(JSON.stringify(obj, null, 2));

  // ---- 1) datas: texto "AAAA-MM-DD" -> Date ----
  const paraData = t => (typeof t === 'string' && t) ? new Date(t + 'T00:00:00Z') : t;

  banco.pets.find().forEach(doc => {
    (doc.vacinas      || []).forEach(v => { v.dt_aplicacao = paraData(v.dt_aplicacao); v.dt_proxima_dose = paraData(v.dt_proxima_dose); });
    (doc.consultas    || []).forEach(c => { c.dt_consulta  = paraData(c.dt_consulta); });
    (doc.medicamentos || []).forEach(m => { m.dt_inicio = paraData(m.dt_inicio); m.dt_fim = paraData(m.dt_fim); });
    (doc.lembretes    || []).forEach(l => { l.dt_lembrete  = paraData(l.dt_lembrete); });
    banco.pets.replaceOne({ _id: doc._id }, doc);
  });
  console.log('Datas convertidas. Documentos na colecao: ' + banco.pets.countDocuments());

  // ---- 2) validacao de schema ($jsonSchema) ----
  banco.runCommand({
    collMod: 'pets',
    validationLevel: 'moderate',
    validator: {
      $jsonSchema: {
        bsonType: 'object',
        required: ['id_pet', 'nm_pet', 'ds_especie', 'tutor'],
        properties: {
          id_pet:         { bsonType: 'number' },
          nm_pet:         { bsonType: 'string' },
          ds_especie:     { bsonType: 'string' },
          nr_idade:       { bsonType: ['number', 'null'], minimum: 0 },
          nr_peso:        { bsonType: ['number', 'null'], minimum: 0 },
          ds_nivel_risco: { bsonType: 'string' },
          tutor: {
            bsonType: 'object',
            required: ['id_tutor', 'nm_tutor', 'ds_email'],
            properties: {
              id_tutor: { bsonType: 'number' },
              nm_tutor: { bsonType: 'string' },
              ds_email: { bsonType: 'string' }
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
          }
        }
      }
    }
  });

  // ---- 3) indices ----
  banco.pets.createIndex({ id_pet: 1 }, { unique: true });
  banco.pets.createIndex({ 'tutor.ds_email': 1 });
  banco.pets.createIndex({ ds_nivel_risco: 1 });
  banco.pets.createIndex({ 'vacinas.dt_proxima_dose': 1 });

  // ---- 4) consultas de exemplo ----
  console.log('--- 4.1) Todos os pets ---');
  mostrar(banco.pets.find({}, { _id: 0, nm_pet: 1, ds_especie: 1, ds_nivel_risco: 1 }).toArray());

  console.log('--- 4.2) Pets com risco ALTO e o tutor ---');
  mostrar(banco.pets.find({ ds_nivel_risco: 'ALTO' }, { _id: 0, nm_pet: 1, 'tutor.nm_tutor': 1 }).toArray());

  console.log('--- 4.3) Vacinas com proxima dose ate 31/03/2027 ---');
  mostrar(banco.pets.find(
    { 'vacinas.dt_proxima_dose': { $lte: new Date('2027-03-31T00:00:00Z') } },
    { _id: 0, nm_pet: 1, 'vacinas.nm_vacina': 1, 'vacinas.dt_proxima_dose': 1 }
  ).toArray());

  console.log('--- 4.4) Peso medio e quantidade por especie ---');
  mostrar(banco.pets.aggregate([
    { $group: { _id: '$ds_especie', qtd_pets: { $sum: 1 }, peso_medio: { $avg: '$nr_peso' } } },
    { $sort: { _id: 1 } }
  ]).toArray());

  console.log('--- 4.5) Lembretes pendentes ---');
  mostrar(banco.pets.aggregate([
    { $unwind: '$lembretes' },
    { $match: { 'lembretes.ds_status': 'PENDENTE' } },
    { $project: { _id: 0, nm_pet: 1, mensagem: '$lembretes.ds_mensagem', data: '$lembretes.dt_lembrete' } },
    { $sort: { data: 1 } }
  ]).toArray());
})();
