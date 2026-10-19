trigger HabilitacaoTrigger on Habilitacao__c(before insert, before update) {
    if (RaizHabilitacaoHandler.ativo()) {
        RaizHabilitacaoHandler.antesDeGravar(Trigger.new);
    }
}
