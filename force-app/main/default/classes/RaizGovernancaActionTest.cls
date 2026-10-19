/**
 * RaizGovernancaActionTest — automacao de governanca documental (Onda 7).
 *
 * Os testes chamam a acao diretamente DEPOIS de colocar o documento em revisao.
 * Se o Flow RAIZ_Governanca_Revisao estiver ativo, ele ja rodou uma vez na
 * mesma transacao: a chamada direta e a "segunda execucao" e prova a
 * idempotencia. Se o Flow estiver inativo, a chamada direta e a primeira.
 * Os asserts valem nos dois casos.
 */
@IsTest
private class RaizGovernancaActionTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
        RaizTestData.criarAprovador();
        insert new Project__c(Name = RaizKnowledgeService.PROJETO_RAIZ);
    }

    private static Business_Rule__c doc(String status, Boolean completo, Id revisor, Date prazo) {
        Processo_Critico__c p = RaizTestData.processo(RaizTestData.conta('ACT').Id, 'Proc acao', 'Critico', 1, 100, 2);
        insert p;
        Business_Rule__c d = new Business_Rule__c(
            Title__c = 'Doc automação',
            Status__c = status,
            Criticality__c = 'Critica',
            Domain__c = 'Fiscal',
            Processo_Critico__c = p.Id,
            Project__c = [SELECT Id FROM Project__c LIMIT 1].Id,
            Revisor__c = revisor,
            Prazo_Revisao__c = prazo
        );
        if (completo) {
            d.Proposito_Documento__c = '<p>Para que serve</p>';
            d.Descricao_Demanda__c = '<p>Passo a passo</p>';
            d.Criterios_Aceite__c = '<p>Resultado</p>';
            d.Cenarios_Teste__c = '<p>Exceções</p>';
        }
        insert d;
        return d;
    }

    private static List<Task> tarefas(Id docId) {
        return [SELECT Id, OwnerId, ActivityDate, Priority, Status, Subject FROM Task WHERE WhatId = :docId];
    }

    private static List<RAIZ_Log_Execucao__c> logs(Id docId, String status) {
        return [
            SELECT Id, Status__c, Etapa__c, Execucoes__c, Mensagem__c, Chave__c
            FROM RAIZ_Log_Execucao__c
            WHERE Registro_Id__c = :docId AND Status__c = :status
        ];
    }

    @IsTest
    static void sucessoCriaTarefaUmaVezSo() {
        User revisor = RaizTestData.usuarioAprovador();
        Id docId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            docId = doc('Em Analise', true, revisor.Id, Date.today().addDays(3)).Id;
            Test.startTest();
            RaizGovernancaAction.submeter(docId);
            RaizGovernancaAction.submeter(docId);
            Test.stopTest();
        }
        List<Task> ts = tarefas(docId);
        System.assertEquals(1, ts.size(), 'uma tarefa, mesmo rodando de novo');
        System.assertEquals(revisor.Id, ts[0].OwnerId);
        System.assertEquals(Date.today().addDays(3), ts[0].ActivityDate);
        System.assertEquals('High', ts[0].Priority, 'documento crítico');
        System.assert(ts[0].Subject.startsWith(RaizGovernancaAction.PREFIXO_TAREFA));

        Business_Rule__c d = [SELECT Governanca_Status__c, Data_Solicitacao_Revisao__c, Status__c FROM Business_Rule__c WHERE Id = :docId];
        System.assertEquals('Em Analise', d.Status__c, 'a automação não muda o status');
        System.assert(d.Governanca_Status__c.startsWith('Em revisão com '), d.Governanca_Status__c);
        System.assertNotEquals(null, d.Data_Solicitacao_Revisao__c);

        List<RAIZ_Log_Execucao__c> ok = logs(docId, 'Sucesso');
        System.assertEquals(1, ok.size(), 'um registro de log por submissão');
        System.assert(ok[0].Execucoes__c >= 2, 'a segunda execução atualizou o mesmo log');
        System.assert(ok[0].Mensagem__c.contains('Tarefa de revisão'), ok[0].Mensagem__c);
    }

    @IsTest
    static void incompletoFicaBloqueadoSemTarefa() {
        Id docId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            docId = doc('Em Analise', false, null, null).Id;
            RaizGovernancaAction.submeter(docId);
            RaizGovernancaAction.submeter(docId);
        }
        System.assertEquals(0, tarefas(docId).size());
        Business_Rule__c d = [SELECT Governanca_Status__c FROM Business_Rule__c WHERE Id = :docId];
        System.assert(d.Governanca_Status__c.startsWith('Bloqueado: falta '), d.Governanca_Status__c);
        System.assert(d.Governanca_Status__c.contains('Revisor'));
        List<RAIZ_Log_Execucao__c> b = logs(docId, 'Bloqueado');
        System.assertEquals(1, b.size());
        System.assert(b[0].Execucoes__c >= 2);
        System.assertEquals(0, logs(docId, 'Sucesso').size());
    }

    @IsTest
    static void rascunhoEIgnoradoEErroViraLog() {
        Id docId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            docId = doc('Draft', true, RaizTestData.usuarioAprovador().Id, null).Id;
            RaizGovernancaAction.Requisicao r = new RaizGovernancaAction.Requisicao();
            r.documentoId = docId;
            r.acao = 'submeter';
            RaizGovernancaAction.executar(new List<RaizGovernancaAction.Requisicao>{ r });
        }
        System.assertEquals(0, tarefas(docId).size());
        System.assertEquals(1, logs(docId, 'Ignorado').size());

        // Documento inexistente: nao lanca, registra.
        RaizGovernancaAction.Requisicao inexistente = new RaizGovernancaAction.Requisicao();
        inexistente.documentoId = null;
        inexistente.acao = 'escalar';
        RaizGovernancaAction.executar(new List<RaizGovernancaAction.Requisicao>{ inexistente });
        System.assertEquals(1, [SELECT COUNT() FROM RAIZ_Log_Execucao__c WHERE Status__c = 'Erro']);
    }

    @IsTest
    static void loteAcimaDoLimiteNaoQuebra() {
        List<RaizGovernancaAction.Requisicao> rs = new List<RaizGovernancaAction.Requisicao>();
        for (Integer i = 0; i < RaizGovernancaAction.LIMITE_LOTE + 2; i++) {
            RaizGovernancaAction.Requisicao r = new RaizGovernancaAction.Requisicao();
            r.acao = 'submeter';
            rs.add(r);
        }
        RaizGovernancaAction.executar(rs);
        System.assertEquals(2, [SELECT COUNT() FROM RAIZ_Log_Execucao__c WHERE Chave__c LIKE 'LOTE:%']);
    }

    @IsTest
    static void escalonaUmaVezQuandoOPrazoVence() {
        User revisor = RaizTestData.usuarioAprovador();
        Id vencido;
        Id noPrazo;
        System.runAs(RaizTestData.usuarioRaiz()) {
            vencido = doc('Em Analise', true, revisor.Id, Date.today().addDays(-1)).Id;
            noPrazo = doc('Em Analise', true, revisor.Id, Date.today().addDays(2)).Id;
            RaizGovernancaAction.submeter(vencido);
            RaizGovernancaAction.escalar(vencido);
            RaizGovernancaAction.escalar(vencido);
            RaizGovernancaAction.escalar(noPrazo);
        }
        Business_Rule__c d = [SELECT Escalonado_Em__c, Governanca_Status__c FROM Business_Rule__c WHERE Id = :vencido];
        System.assertNotEquals(null, d.Escalonado_Em__c);
        System.assert(d.Governanca_Status__c.startsWith('Revisão atrasada'), d.Governanca_Status__c);
        System.assertEquals('High', tarefas(vencido)[0].Priority);
        Integer escal = 0;
        for (RAIZ_Log_Execucao__c l : logs(vencido, 'Sucesso')) {
            if (l.Etapa__c == 'escalonamento') escal++;
        }
        System.assertEquals(1, escal, 'escala uma vez só');
        System.assertEquals(1, logs(vencido, 'Ignorado').size(), 'a repetição vira Ignorado');
        System.assertEquals(null, [SELECT Escalonado_Em__c FROM Business_Rule__c WHERE Id = :noPrazo].Escalonado_Em__c);
        System.assertEquals(1, logs(noPrazo, 'Ignorado').size());
    }

    @IsTest
    static void aprovarNoHubEncerraATarefa() {
        User revisor = RaizTestData.usuarioAprovador();
        Id docId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            docId = doc('Em Analise', true, revisor.Id, Date.today().addDays(3)).Id;
            RaizGovernancaAction.submeter(docId);
        }
        System.runAs(revisor) {
            RaizKnowledgeService.moverDocumento(docId, 1);
        }
        Business_Rule__c d = [SELECT Status__c, Governanca_Status__c FROM Business_Rule__c WHERE Id = :docId];
        System.assertEquals('Aprovada', d.Status__c);
        System.assert(d.Governanca_Status__c.startsWith('Aprovado em'), d.Governanca_Status__c);
        for (Task t : tarefas(docId)) System.assertEquals('Completed', t.Status);
    }

    @IsTest
    static void cockpitEHubMostramAGovernanca() {
        User revisor = RaizTestData.usuarioAprovador();
        System.runAs(RaizTestData.usuarioRaiz()) {
            Business_Rule__c ok = doc('Em Analise', true, revisor.Id, Date.today().addDays(-2));
            Business_Rule__c bloq = doc('Em Analise', false, null, null);
            RaizGovernancaAction.submeter(ok.Id);
            RaizGovernancaAction.submeter(bloq.Id);

            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
            System.assertEquals(2, c.govEmRevisao);
            System.assertEquals(1, c.govAtrasadas);
            System.assertEquals(1, c.govBloqueadas);
            System.assertEquals(1, c.govSemPrazo);

            Boolean achou = false;
            for (RaizKnowledgeService.Coluna col : RaizKnowledgeService.getQuadro(null).colunas) {
                for (RaizKnowledgeService.Cartao k : col.cartoes) {
                    if (k.id == bloq.Id) {
                        achou = true;
                        System.assert(k.governanca.startsWith('Bloqueado'), k.governanca);
                    }
                }
            }
            System.assert(achou);
        }
    }

    @IsTest
    static void notificacaoSemDestinatarioNaoQuebra() {
        System.assertEquals(false, RaizGovernancaAction.notificar(new Set<Id>(), 't', 'c', null));
    }
}
