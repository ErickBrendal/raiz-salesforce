RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
for (RaizCockpitService.Fatia f : c.estadosCobertura) System.debug(LoggingLevel.ERROR, 'RAIZ ESTADO: ' + f.rotuloExibicao + ' = ' + f.quantidade + ' (' + f.percentual + '%)');
System.debug(LoggingLevel.ERROR, 'RAIZ FONTE: habilitacao=' + c.coberturaEvidenciada + ' declarado=' + c.coberturaDeclarada + ' sem dado=' + c.informacaoInsuficiente);
System.debug(LoggingLevel.ERROR, 'RAIZ MITIGACAO: abertos=' + c.planosAbertos + ' atrasados=' + c.planosAtrasados + ' score ' + c.scoreInicialPlanos + ' -> ' + c.scoreAtualPlanos + ' | pontos unicos sem plano=' + c.pontosUnicosSemPlano + ' | sem permissao=' + c.semPermissao);
