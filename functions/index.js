const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

admin.initializeApp();
const db = admin.firestore();

exports.reallocateStockItem = functions.https.onRequest((req, res) => {
  // Habilita o CORS para permitir chamadas do seu app
  cors(req, res, async () => {
    // ##### NOSSA NOVA VERIFICAÇÃO DE SEGURANÇA #####
    // 1. CRIE UMA SENHA LONGA E SEGURA.
    //    Pode usar um gerador de senhas online. Ex: "MinhaSenhaSuperSecretaParaOApp123!@#"
    // 2. SUBSTITUA O TEXTO ABAIXO PELA SUA SENHA.
    const MY_SECRET_KEY = "964069882pP@";

    if (req.headers.authorization !== `Bearer ${MY_SECRET_KEY}`) {
      console.error("Tentativa de acesso não autorizado.");
      return res.status(401).send({ error: { message: "Não autorizado." } });
    }

    const {
      productId, logoType, sourceOrderId, targetOrderId,
      targetOrderClientName, targetOrderDeliveryDate, quantity
    } = req.body.data;

    if (!productId || !logoType || !targetOrderId || !quantity) {
      return res.status(400).send({ error: { message: "Dados insuficientes." } });
    }

    try {
      await db.runTransaction(async (transaction) => {
        let sourceQuery = db.collection("stock_items")
          .where("productId", "==", productId)
          .where("logoType", "==", logoType)
          .where("status", "==", "emEstoque")
          .where("orderId", "==", sourceOrderId);

        sourceQuery = sourceQuery.limit(quantity);
        const sourceSnapshot = await transaction.get(sourceQuery);

        if (sourceSnapshot.docs.length < quantity) {
          throw new Error(`A quantidade necessária (${quantity}) de itens não foi encontrada.`);
        }

        const pendingQuery = db.collection("stock_items")
          .where("orderId", "==", targetOrderId)
          .where("productId", "==", productId)
          .where("logoType", "==", logoType)
          .where("status", "==", "aguardandoProducao")
          .limit(sourceSnapshot.docs.length);
        const pendingSnapshot = await transaction.get(pendingQuery);

        const reallocatedFromLabel = sourceOrderId == null ?
          "Estoque Geral (Manual)" :
          `Pedido #${sourceOrderId.substring(0, 6).toUpperCase()} (Manual)`;

        sourceSnapshot.docs.forEach((doc) => {
          const itemData = doc.data();
          transaction.delete(doc.ref);
          const newItemRef = db.collection("stock_items").doc();
          transaction.set(newItemRef, {
            ...itemData,
            orderId: targetOrderId,
            clientName: targetOrderClientName || "",
            deliveryDeadline: targetOrderDeliveryDate ? admin.firestore.Timestamp.fromDate(new Date(targetOrderDeliveryDate)) : admin.firestore.Timestamp.now(),
            reallocatedFrom: reallocatedFromLabel,
            creationDate: admin.firestore.Timestamp.now(),
          });
          if (sourceOrderId != null) {
            const replacementItemRef = db.collection("stock_items").doc();
            transaction.set(replacementItemRef, {
              ...itemData,
              orderId: sourceOrderId,
              status: "aguardandoProducao",
              creationDate: admin.firestore.Timestamp.now(),
              reallocatedFrom: `Emprestado para Pedido #${targetOrderId.substring(0, 6).toUpperCase()}`,
            });
          }
        });
        pendingSnapshot.docs.forEach((doc) => transaction.delete(doc.ref));
      });
      return res.status(200).send({ result: { status: "success", message: "Item realocado." } });
    } catch (error) {
      console.error("Erro na transação de realocação:", error);
      return res.status(500).send({ error: { message: error.message || "Erro interno no servidor." } });
    }
  });
});