/**
 * RaizHabilitacaoVencimentoJob
 * ---------------------------------------------------------------------------
 * Rotina diaria. Filtro de roll-up nao aceita TODAY(), entao a contagem
 * Aptos_Habilitados__c so fica correta se alguem marcar como Vencida a
 * habilitacao que expirou sem ser editada. E isso que este job faz — e, pelo
 * mesmo motivo, suspende Apto de profissional inativo.
 *
 * Agendar: System.schedule(RaizHabilitacaoVencimentoJob.NOME,
 *                          '0 0 5 * * ?', new RaizHabilitacaoVencimentoJob());
 */
public with sharing class RaizHabilitacaoVencimentoJob implements Database.Batchable<SObject>, Schedulable {
    public static final String NOME = 'RAIZ - vencimento de habilitacoes';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date hoje = Date.today();
        return Database.getQueryLocator(
            [
                SELECT Id, Status__c, Valida_Ate__c, Profissional__r.Ativo__c
                FROM Habilitacao__c
                WHERE Status__c = 'Apto' AND (Valida_Ate__c < :hoje OR Profissional__r.Ativo__c = FALSE)
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Habilitacao__c> escopo) {
        Date hoje = Date.today();
        for (Habilitacao__c h : escopo) {
            h.Status__c = (h.Valida_Ate__c != null && h.Valida_Ate__c < hoje)
                ? RaizHabilitacaoHandler.VENCIDA
                : RaizHabilitacaoHandler.SUSPENSA;
        }
        update escopo;
    }

    public void finish(Database.BatchableContext bc) {
        return;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RaizHabilitacaoVencimentoJob(), 200);
    }
}
