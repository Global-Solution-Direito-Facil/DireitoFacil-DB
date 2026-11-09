// ============================================================================
// PROJETO: DIREITO FACIL - CITIZENTECH (GLOBAL SOLUTION 2026/2)
// DISCIPLINA: MASTERING RELATIONAL AND NON-RELATIONAL DATABASE
// ARQUIVO: mongo/02_consultas.js
// DESCRICAO: 3 consultas (2 find + 1 aggregate) equivalentes aos relatorios
//            de oracle/07_RELATORIOS_ORACLE.sql
// EXECUCAO: mongosh "mongodb://localhost:27017" --file mongo/02_consultas.js
// ============================================================================

db = db.getSiblingDB("citizentech");

print("\n=== RELATORIO 1 (find): direitos ELEGIVEIS de Lucas Almeida ===");
db.casos.find(
  { "pessoa.idPessoa": 1, "avaliacao.resultado": "ELEGIVEL" },
  { _id: 1, "direito.codigo": 1, status: 1 }
).sort({ "direito.idDireito": 1 }).forEach(d => printjson(d));

print("\n=== RELATORIO 2 (find): casos em andamento com prazo ate 05/12/2026 ===");
db.casos.find(
  {
    status: { $in: ["ABERTO", "EM_ANALISE", "DOCUMENTOS_PENDENTES"] },
    dtPrazo: { $lte: ISODate("2026-12-05T00:00:00Z") }
  },
  { _id: 1, "pessoa.nome": 1, "direito.codigo": 1, status: 1, dtPrazo: 1 }
).sort({ dtPrazo: 1, _id: 1 }).forEach(d => printjson(d));

print("\n=== RELATORIO 3 (aggregate): panorama por pessoa ===");
db.casos.aggregate([
  { $group: {
      _id: "$pessoa.nome",
      totalCasos: { $sum: 1 },
      elegiveis:  { $sum: { $cond: [{ $eq: ["$avaliacao.resultado", "ELEGIVEL"] }, 1, 0] } },
      possiveis:  { $sum: { $cond: [{ $eq: ["$avaliacao.resultado", "POSSIVEL"] }, 1, 0] } },
      concedidos: { $sum: { $cond: [{ $eq: ["$status", "CONCEDIDO"] }, 1, 0] } }
  } },
  { $sort: { totalCasos: -1, _id: 1 } }
]).forEach(d => printjson(d));

print("\n=== COMPARACAO RAPIDA: totais (devem bater com o Oracle) ===");
printjson({ totalCasos: db.casos.countDocuments(), totalLaudos: db.laudos.countDocuments() });
