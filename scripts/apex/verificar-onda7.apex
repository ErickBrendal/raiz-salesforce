// RAIZ Onda 7 — verificacao somente leitura.
List<FlowDefinitionView> f = [SELECT IsActive, ActiveVersionId FROM FlowDefinitionView WHERE ApiName = 'RAIZ_Governanca_Revisao'];
System.debug(LoggingLevel.ERROR, 'RAIZ FLOW: ' + (f.isEmpty() ? 'nao encontrado' : (f[0].IsActive ? 'ATIVO' : 'INATIVO')));
System.debug(LoggingLevel.ERROR, 'RAIZ NOTIFICACAO: ' + [SELECT COUNT() FROM CustomNotificationType WHERE DeveloperName = 'RAIZ_Revisao_Documento']);
for (AggregateResult ar : [SELECT Status__c s, COUNT(Id) n, SUM(Execucoes__c) e FROM RAIZ_Log_Execucao__c GROUP BY Status__c]) {
    System.debug(LoggingLevel.ERROR, 'RAIZ LOG ' + ar.get('s') + ': registros=' + ar.get('n') + ' execucoes=' + ar.get('e'));
}
for (Business_Rule__c d : [SELECT Title__c, Status__c, Governanca_Status__c FROM Business_Rule__c WHERE Title__c LIKE '%(demonstração)' ORDER BY CreatedDate]) {
    System.debug(LoggingLevel.ERROR, 'RAIZ DOC DEMO: ' + d.Title__c + ' | ' + d.Status__c + ' | ' + d.Governanca_Status__c + ' | tarefas abertas=' + [SELECT COUNT() FROM Task WHERE WhatId = :d.Id AND IsClosed = false]);
}
RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
System.debug(LoggingLevel.ERROR, 'RAIZ COCKPIT GOVERNANCA: em revisao=' + c.govEmRevisao + ' atrasadas=' + c.govAtrasadas + ' bloqueadas=' + c.govBloqueadas + ' sem prazo=' + c.govSemPrazo);
System.debug(LoggingLevel.ERROR, 'RAIZ CARTOES RAIZ NO KANBAN: ' + [SELECT COUNT() FROM CRM_Kanban_Task__c WHERE Name LIKE 'RAIZ · %']);
