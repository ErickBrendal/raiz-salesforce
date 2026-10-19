// RAIZ Onda 9 — sincroniza o GitHub e liga a release v1.0.0 a implantacao da Onda 9-10 (se ambas existirem).
RaizGitHubService.Resultado r = RaizGitHubService.sincronizar();
System.debug(LoggingLevel.ERROR, 'RAIZ GITHUB: ' + r.status + ' | HTTP ' + r.codigoHttp + ' | ' + r.mensagem);
List<RAIZ_Release__c> rel = [SELECT Id, Tag__c FROM RAIZ_Release__c WHERE Tag__c = 'v1.0.0' LIMIT 1];
List<RAIZ_Implantacao__c> imp = [SELECT Id, Deploy_Id__c, Release__c FROM RAIZ_Implantacao__c WHERE Onda__c = 'Ondas 9-10' AND Resultado__c = 'Sucesso' ORDER BY Executado_Em__c DESC LIMIT 1];
if (!rel.isEmpty() && !imp.isEmpty()) {
    if (imp[0].Release__c != rel[0].Id) { imp[0].Release__c = rel[0].Id; update imp; }
    System.debug(LoggingLevel.ERROR, 'RAIZ RASTREABILIDADE: release v1.0.0 ligada ao deploy ' + imp[0].Deploy_Id__c);
} else {
    System.debug(LoggingLevel.ERROR, 'RAIZ RASTREABILIDADE: ' + (rel.isEmpty() ? 'release v1.0.0 ainda nao sincronizada' : 'sem implantacao da Onda 9-10 registrada') + '; nada ligado.');
}
