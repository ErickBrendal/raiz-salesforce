trigger ProfissionalTrigger on Profissional__c(after update) {
    RaizHabilitacaoHandler.aposAtualizarProfissional(Trigger.new, Trigger.oldMap);
}
