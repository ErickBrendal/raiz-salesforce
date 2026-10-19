// RAIZ Onda 8 — (1) ajusta o cartao de documento bloqueado (achado da Onda 7) e (2) roda o verificador.
Integer ajustados = 0;
for (Business_Rule__c d : [SELECT Id FROM Business_Rule__c WHERE Status__c = 'Em Analise' AND Governanca_Status__c LIKE 'Bloqueado%']) {
    RaizGovernancaService.Cartao c = RaizGovernancaService.sincronizarCartao(d.Id);
    System.debug(LoggingLevel.ERROR, 'RAIZ CARTAO BLOQUEADO: ' + c.acao + ' -> ' + c.etapa + (c.aviso == null ? '' : ' | ' + c.aviso));
    ajustados++;
}
RaizEngineeringVerifier.Resultado r = RaizEngineeringVerifier.executar();
System.debug(LoggingLevel.ERROR, 'RAIZ VERIFICADOR: itens=' + r.total + ' verificados=' + r.verificados + ' falhas=' + r.falhas + ' nao verificaveis=' + r.naoVerificaveis + ' planejados=' + r.planejados);
for (RAIZ_Engineering_Status__c s : [SELECT Name, API_Name__c, Estado_Validacao__c, Resultado_Verificacao__c FROM RAIZ_Engineering_Status__c WHERE Estado_Validacao__c IN ('Falhou', 'Nao verificavel') ORDER BY Nivel__c, Name]) {
    System.debug(LoggingLevel.ERROR, 'RAIZ PENDENTE: ' + s.Estado_Validacao__c + ' | ' + s.API_Name__c + ' | ' + s.Resultado_Verificacao__c);
}
RaizEngineeringService.Painel p = RaizEngineeringService.getPainel();
for (RaizEngineeringService.Indicador i : p.indicadores) System.debug(LoggingLevel.ERROR, 'RAIZ INDICADOR: ' + i.rotulo + ' = ' + i.valor);
