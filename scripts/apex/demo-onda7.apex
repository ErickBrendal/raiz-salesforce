// RAIZ Onda 7 — cenario de demonstracao da automacao (dados ficticios).
// Usa o CADASTRO GUIADO de verdade (RaizJourneyService.salvar) como o usuario que roda o script.
// Cria 3 documentos em processos do Backlog:
//   A) completo, revisor = Revisor Demo, prazo em 5 dias       -> sucesso (tarefa, Kanban, notificacao, log)
//   B) sem etapas e sem revisor, encaminhado mesmo assim (D6) -> bloqueado pela automacao (cenario de erro)
//   C) completo, prazo HOJE                                    -> amanha o caminho agendado escala (atraso)
// Idempotente: processo que ja tem documento e pulado.
if (![SELECT IsActive FROM FlowDefinitionView WHERE ApiName = 'RAIZ_Governanca_Revisao' LIMIT 1].IsActive) {
    System.debug(LoggingLevel.ERROR, 'RAIZ DEMO: o Flow RAIZ_Governanca_Revisao esta INATIVO. Ative-o e rode de novo. Nada foi criado.');
    return;
}
List<User> rev = [SELECT Id, Name FROM User WHERE Username LIKE 'revisor.demo.raiz.%' AND IsActive = true LIMIT 1];
if (rev.isEmpty()) System.debug(LoggingLevel.ERROR, 'RAIZ DEMO: Revisor Demo nao encontrado; A e C tambem vao ficar bloqueados por falta de revisor.');
RaizJourneyService.Contexto ctx = RaizJourneyService.getContexto();
List<RaizJourneyService.ProcessoResumo> livres = new List<RaizJourneyService.ProcessoResumo>();
for (RaizJourneyService.ProcessoResumo p : ctx.processos) if (p.situacaoDocumento == 'Sem documento') livres.add(p);
if (livres.size() < 3) { System.debug(LoggingLevel.ERROR, 'RAIZ DEMO: menos de 3 processos sem documento; nada criado.'); return; }
List<String> rotulos = new List<String>{ 'A (sucesso)', 'B (bloqueado)', 'C (vence hoje)' };
for (Integer i = 0; i < 3; i++) {
    RaizJourneyService.ProcessoResumo p = livres[i];
    RaizJourneyService.Dados x = new RaizJourneyService.Dados();
    x.processoId = p.id;
    x.titulo = ('Registro — ' + p.nome + ' (demonstração)').left(120);
    x.tipo = 'Procedimento operacional';
    x.categoria = 'Outro';
    x.criticidade = p.criticidadeDocumento == null ? 'Alta' : p.criticidadeDocumento;
    x.resumo = '<p>Procedimento de demonstração do RAIZ (dados fictícios): como executar "' + p.nome + '" sem depender de uma única pessoa.</p>';
    x.palavrasChave = 'demonstração, raiz';
    x.dataReferencia = Date.today();
    x.proximaRevisao = Date.today().addMonths(6);
    if (i != 1) {
        x.revisorId = rev.isEmpty() ? null : rev[0].Id;
        x.prazoRevisao = i == 0 ? Date.today().addDays(5) : Date.today();
        x.preRequisitos = '<p>Acesso ao sistema de origem (fictício).</p>';
        x.etapas = '<ol><li>Conferir os dados de entrada.</li><li>Executar a rotina.</li><li>Validar o resultado com a área.</li></ol>';
        x.resultadoEsperado = '<p>Rotina concluída e conferida, sem pendência.</p>';
        x.excecoes = '<p>Dado de entrada inconsistente: devolver à área de origem antes de executar.</p>';
        x.contingencia = '<p>Executar manualmente pela planilha de contingência (fictícia) e registrar.</p>';
    }
    try {
        RaizJourneyService.Resultado r = RaizJourneyService.salvar(JSON.serialize(x), true);
        Business_Rule__c d = [SELECT Status__c, Governanca_Status__c FROM Business_Rule__c WHERE Id = :r.documentoId];
        System.debug(LoggingLevel.ERROR, 'RAIZ DEMO ' + rotulos[i] + ': ' + p.nome + ' -> ' + d.Status__c + ' | ' + d.Governanca_Status__c + ' | tarefas=' + [SELECT COUNT() FROM Task WHERE WhatId = :r.documentoId] + ' | ' + r.cartao.acao);
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'RAIZ DEMO ' + rotulos[i] + ': nao criado: ' + e.getMessage());
    }
}
