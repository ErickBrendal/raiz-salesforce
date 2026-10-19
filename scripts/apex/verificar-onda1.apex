// RAIZ Onda 1 — verificacao SOMENTE LEITURA. Imprime estados e confere formula x motor.
Integer ok = 0, diverg = 0;
Map<String, Integer> estados = new Map<String, Integer>();
Map<String, Integer> fontes = new Map<String, Integer>();
Integer pu = 0; Decimal expo = 0; Integer incompletas = 0;
for (Processo_Critico__c p : [
    SELECT Name, Criticidade__c, Impacto_Hora__c, Horas_Para_Restabelecer__c, Atualizado__c, Pessoas_Aptas__c,
           Habilitacoes_Registradas__c, Aptos_Habilitados__c, Aptos_Efetivos__c, Estado_Cobertura__c,
           Fonte_Cobertura__c, Ponto_Unico_de_Falha__c, Exposicao_Financeira__c, Exposicao_Completa__c,
           Risco_Score__c, Farol__c
    FROM Processo_Critico__c ORDER BY Name
]) {
    Integer reg = p.Habilitacoes_Registradas__c == null ? 0 : p.Habilitacoes_Registradas__c.intValue();
    Integer hab = p.Aptos_Habilitados__c == null ? 0 : p.Aptos_Habilitados__c.intValue();
    Integer aptos = RaizRiskEngine.aptosEfetivos(reg, hab, p.Pessoas_Aptas__c);
    RaizRiskEngine.Avaliacao a = RaizRiskEngine.avaliar(p, aptos);
    Boolean igual = a.estado == p.Estado_Cobertura__c && a.pontoUnico == p.Ponto_Unico_de_Falha__c
        && a.exposicao == p.Exposicao_Financeira__c && a.score == p.Risco_Score__c.intValue() && a.farol == p.Farol__c;
    if (igual) ok++; else { diverg++; System.debug(LoggingLevel.ERROR, 'RAIZ DIVERGENCIA formula x motor: ' + p.Name); }
    estados.put(p.Estado_Cobertura__c, (estados.containsKey(p.Estado_Cobertura__c) ? estados.get(p.Estado_Cobertura__c) : 0) + 1);
    fontes.put(p.Fonte_Cobertura__c, (fontes.containsKey(p.Fonte_Cobertura__c) ? fontes.get(p.Fonte_Cobertura__c) : 0) + 1);
    if (p.Ponto_Unico_de_Falha__c) pu++;
    expo += p.Exposicao_Financeira__c == null ? 0 : p.Exposicao_Financeira__c;
    if (!p.Exposicao_Completa__c) incompletas++;
    if (p.Pessoas_Aptas__c != null && aptos != null && p.Pessoas_Aptas__c.intValue() != aptos) {
        System.debug(LoggingLevel.ERROR, 'RAIZ DECLARADO x EVIDENCIADO: ' + p.Name + ' declarado=' + p.Pessoas_Aptas__c.intValue() + ' evidenciado=' + aptos);
    }
}
System.debug(LoggingLevel.ERROR, 'RAIZ VERIFICA: formula=motor ' + ok + ' | divergencias ' + diverg);
System.debug(LoggingLevel.ERROR, 'RAIZ VERIFICA: estados ' + estados + ' | fontes ' + fontes);
System.debug(LoggingLevel.ERROR, 'RAIZ VERIFICA: pontos unicos ' + pu + ' | exposicao ' + expo + ' | exposicao incompleta ' + incompletas);
RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
for (RaizCockpitService.Indicador i : c.indicadores) System.debug(LoggingLevel.ERROR, 'RAIZ COCKPIT: ' + i.chave + ' = ' + i.valorFormatado + ' (' + i.tom + ')');
System.debug(LoggingLevel.ERROR, 'RAIZ COCKPIT: insuficiente=' + c.informacaoInsuficiente + ' evidenciado=' + c.coberturaEvidenciada + ' declarado=' + c.coberturaDeclarada);
for (String r : c.ressalvas) System.debug(LoggingLevel.ERROR, 'RAIZ RESSALVA: ' + r);
List<RaizSimulationService.Opcao> ops = RaizSimulationService.getProfissionais(null);
if (!ops.isEmpty()) {
    RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(null, Id.valueOf(ops[0].value));
    System.debug(LoggingLevel.ERROR, 'RAIZ SIMULADOR: ' + r.pessoa + ' param=' + r.param + ' frageis=' + r.ficamFrageis
        + ' continuam=' + r.continuam + ' exposicao=' + r.exposicao + ' horas=' + r.horasParaRestabelecer);
    System.debug(LoggingLevel.ERROR, 'RAIZ SIMULADOR: ' + r.veredito);
}
