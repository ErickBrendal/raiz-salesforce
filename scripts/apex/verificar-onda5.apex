RaizKnowledgeService.Quadro q = RaizKnowledgeService.getQuadro(null);
System.debug(LoggingLevel.ERROR, 'RAIZ HUB: documentos=' + q.documentos + ' publicados=' + q.publicados + ' sem documento=' + q.processosSemDocumento + ' pode aprovar=' + q.podeAprovar);
for (RaizKnowledgeService.Coluna c : q.colunas) System.debug(LoggingLevel.ERROR, 'RAIZ COLUNA: ' + c.rotulo + ' = ' + c.total);
System.debug(LoggingLevel.ERROR, 'RAIZ DOCS FORA DO HUB (sem processo): ' + [SELECT COUNT() FROM Business_Rule__c WHERE Processo_Critico__c = null]);
RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
for (RaizCockpitService.Indicador i : c.indicadores) System.debug(LoggingLevel.ERROR, 'RAIZ COCKPIT: ' + i.rotulo + ' = ' + i.valorFormatado);
