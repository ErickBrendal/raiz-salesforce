// RAIZ Onda 6 — verificacao somente leitura.
Map<String, Schema.SObjectField> f = Schema.SObjectType.Business_Rule__c.fields.getMap();
List<String> novos = new List<String>{ 'tipo_documento__c', 'revisor__c', 'prazo_revisao__c', 'proxima_revisao__c', 'pre_requisitos__c', 'plano_contingencia__c', 'referencias__c' };
Integer ok = 0; for (String n : novos) if (f.containsKey(n)) ok++;
System.debug(LoggingLevel.ERROR, 'RAIZ CAMPOS NOVOS: ' + ok + ' de ' + novos.size());
RaizJourneyService.Contexto c = RaizJourneyService.getContexto();
System.debug(LoggingLevel.ERROR, 'RAIZ JORNADA: processos=' + c.processos.size() + ' tipos=' + c.tipos.size() + ' revisores elegiveis para voce=' + c.revisores.size());
for (RaizGovernancaService.Revisor r : c.revisores) System.debug(LoggingLevel.ERROR, 'RAIZ REVISOR ELEGIVEL: ' + r.nome);
Map<String, Integer> sit = new Map<String, Integer>();
for (RaizJourneyService.ProcessoResumo p : c.processos) sit.put(p.situacaoDocumento, (sit.containsKey(p.situacaoDocumento) ? sit.get(p.situacaoDocumento) : 0) + 1);
System.debug(LoggingLevel.ERROR, 'RAIZ SITUACAO DOS PROCESSOS: ' + sit);
System.debug(LoggingLevel.ERROR, 'RAIZ CARTOES RAIZ NO KANBAN: ' + [SELECT COUNT() FROM CRM_Kanban_Task__c WHERE Name LIKE 'RAIZ · %']);
System.debug(LoggingLevel.ERROR, 'RAIZ APP: ' + [SELECT COUNT() FROM AppMenuItem WHERE Name = 'RAIZ']);
