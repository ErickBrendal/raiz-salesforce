// RAIZ Onda 3 — verificacao SOMENTE LEITURA.
RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
for (RaizCockpitService.Indicador i : c.indicadores) System.debug(LoggingLevel.ERROR, 'RAIZ COCKPIT: ' + i.rotulo + ' = ' + i.valorFormatado + ' (' + i.tom + ')');
for (RaizCockpitService.PessoaChave p : c.pessoasChave) System.debug(LoggingLevel.ERROR, 'RAIZ CONCENTRACAO: ' + p.nome + ' sozinho=' + p.processosSozinho + ' total=' + p.processosTotal + ' ' + p.exposicaoFmt);
for (String r : c.ressalvas) System.debug(LoggingLevel.ERROR, 'RAIZ RESSALVA: ' + r);
for (RaizCockpitService.Fatia f : c.matrizRisco) System.debug(LoggingLevel.ERROR, 'RAIZ FAROL: ' + f.rotuloExibicao + ' = ' + f.quantidade);
RaizMitigationService.Painel pn = RaizMitigationService.getPainel(null);
System.debug(LoggingLevel.ERROR, 'RAIZ MITIGACAO: abertos=' + pn.planosAbertos + ' atrasados=' + pn.planosAtrasados + ' acoes=' + pn.acoesConcluidas + '/' + pn.acoesTotal + ' sem_plano=' + pn.processosSemPlano);
for (RaizMitigationService.PlanoDTO p : pn.planos) System.debug(LoggingLevel.ERROR, 'RAIZ PLANO: ' + p.processo + ' | ' + p.statusRotulo + ' | ' + p.progresso + '% | atrasado=' + p.atrasado + ' | ' + p.responsavel);
for (RaizMitigationService.Sugestao s : pn.sugestoes) System.debug(LoggingLevel.ERROR, 'RAIZ SUGESTAO: ' + s.processo + ' | ' + s.objetivoRotulo + ' | score ' + s.score);
List<RaizSimulationService.Opcao> ops = RaizSimulationService.getProfissionais(null);
if (!ops.isEmpty()) {
    RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(null, Id.valueOf(ops[0].value));
    System.debug(LoggingLevel.ERROR, 'RAIZ SIMULADOR: ' + ops[0].label + ' | ' + r.veredito);
}
