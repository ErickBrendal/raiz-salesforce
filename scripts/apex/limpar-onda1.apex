// REMOVE somente os dados de demonstracao da Onda 1 (chave RAIZ-PROF-). NAO rodar sem decisao explicita.
List<Profissional__c> pros = [SELECT Id FROM Profissional__c WHERE Chave_Externa__c LIKE 'RAIZ-PROF-%'];
delete [SELECT Id FROM Habilitacao__c WHERE Profissional__c IN :pros];
delete pros;
System.debug(LoggingLevel.ERROR, 'RAIZ: removidos ' + pros.size() + ' profissionais de demonstracao e suas habilitacoes.');
