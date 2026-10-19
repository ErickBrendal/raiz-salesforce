// RAIZ — Quality gate (somente leitura, exceto o verificador gravar evidencias).
RaizEngineeringVerifier.Resultado v = RaizEngineeringVerifier.executar();
System.debug(LoggingLevel.ERROR, 'RAIZ VERIFICADOR: itens=' + v.total + ' verificados=' + v.verificados + ' falhas=' + v.falhas + ' nao verificaveis=' + v.naoVerificaveis + ' planejados=' + v.planejados);
for (RAIZ_Engineering_Status__c s : [SELECT API_Name__c, Estado_Validacao__c, Resultado_Verificacao__c FROM RAIZ_Engineering_Status__c WHERE Estado_Validacao__c IN ('Falhou', 'Nao verificavel') ORDER BY Nivel__c, Name]) {
    System.debug(LoggingLevel.ERROR, 'RAIZ PENDENTE: ' + s.Estado_Validacao__c + ' | ' + s.API_Name__c + ' | ' + s.Resultado_Verificacao__c);
}
for (RaizEngineeringService.Indicador i : RaizEngineeringService.getPainel().indicadores) System.debug(LoggingLevel.ERROR, 'RAIZ INDICADOR: ' + i.rotulo + ' = ' + i.valor);
for (PermissionSet ps : [SELECT Name, (SELECT Id FROM Assignments) FROM PermissionSet WHERE Name IN ('EBL_RAIZ_Cockpit', 'RAIZ_Aprovador', 'RAIZ_Leitor', 'RAIZ_Engenharia')]) {
    System.debug(LoggingLevel.ERROR, 'RAIZ PERMISSAO: ' + ps.Name + ' atribuido a ' + ps.Assignments.size() + ' usuario(s)');
}
System.debug(LoggingLevel.ERROR, 'RAIZ FLOW ATIVO: ' + [SELECT IsActive FROM FlowDefinitionView WHERE ApiName = 'RAIZ_Governanca_Revisao' LIMIT 1].IsActive);
System.debug(LoggingLevel.ERROR, 'RAIZ JOBS: ' + [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'RAIZ%']);
