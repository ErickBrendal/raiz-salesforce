trigger AcaoMitigacaoTrigger on Acao_Mitigacao__c(before insert, before update) {
    RaizMitigationService.carimbarConclusao(Trigger.new);
}
