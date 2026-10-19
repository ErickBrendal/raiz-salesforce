/**
 * RaizLog — grava RAIZ_Log_Execucao__c com chave de idempotencia (RAIZ 4.0).
 * ---------------------------------------------------------------------------
 * Mesma chave = mesma execucao: a segunda vez ATUALIZA o registro (Execucoes + 1)
 * em vez de criar outro. Devolve true quando o registro e novo; quem chama usa
 * isso para nao notificar duas vezes.
 *
 * without sharing, de proposito (ADR-018): o log precisa ser gravado mesmo
 * quando o usuario que disparou a automacao nao tem acesso ao objeto de log.
 * Nunca lanca excecao: falha no log nao pode desfazer a operacao de negocio.
 * Nunca gravar segredo, token ou corpo bruto de resposta HTTP em Mensagem.
 */
public without sharing class RaizLog {
    public static Boolean registrar(String tipo, String etapa, String status, Id registroId, String chave, String mensagem) {
        return registrar(tipo, etapa, status, registroId, chave, mensagem, null);
    }

    public static Boolean registrar(
        String tipo,
        String etapa,
        String status,
        Id registroId,
        String chave,
        String mensagem,
        Integer codigoHttp
    ) {
        try {
            String k = (chave == null ? 'SEM-CHAVE:' + DateTime.now().getTime() : chave).left(255);
            List<RAIZ_Log_Execucao__c> ja = [SELECT Id, Execucoes__c FROM RAIZ_Log_Execucao__c WHERE Chave__c = :k LIMIT 1];
            RAIZ_Log_Execucao__c l = new RAIZ_Log_Execucao__c(
                Tipo__c = tipo,
                Etapa__c = etapa == null ? null : etapa.left(40),
                Status__c = status,
                Registro_Id__c = registroId,
                Chave__c = k,
                Mensagem__c = mensagem == null ? null : mensagem.left(5000),
                Executado_Em__c = DateTime.now(),
                Codigo_HTTP__c = codigoHttp
            );
            if (ja.isEmpty()) {
                l.Execucoes__c = 1;
                insert l;
                return true;
            }
            l.Id = ja[0].Id;
            l.Execucoes__c = (ja[0].Execucoes__c == null ? 1 : ja[0].Execucoes__c) + 1;
            update l;
            return false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'RAIZ LOG falhou: ' + e.getMessage());
            return false;
        }
    }
}
