/**
 * RaizGovernancaServiceTest — revisores, avaliacao de submissao e cartao do Kanban (Onda 6).
 */
@IsTest
private class RaizGovernancaServiceTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
        RaizTestData.criarAprovador();
        insert new Project__c(Name = RaizKnowledgeService.PROJETO_RAIZ);
    }

    private static Id projetoId() {
        return [SELECT Id FROM Project__c WHERE Name = :RaizKnowledgeService.PROJETO_RAIZ LIMIT 1].Id;
    }

    private static Processo_Critico__c processo(String nome) {
        Processo_Critico__c p = RaizTestData.processo(RaizTestData.conta('GOV ' + nome).Id, nome, 'Critico', 1, 100, 2);
        insert p;
        return p;
    }

    private static Business_Rule__c doc(Id processoId, String status) {
        Business_Rule__c d = new Business_Rule__c(
            Title__c = 'Doc gov',
            Status__c = status,
            Criticality__c = 'Alta',
            Domain__c = 'Fiscal',
            Processo_Critico__c = processoId,
            Project__c = projetoId()
        );
        insert d;
        return d;
    }

    @IsTest
    static void revisoresExcluemOAutor() {
        User autor = RaizTestData.usuarioRaiz();
        User revisor = RaizTestData.usuarioAprovador();
        System.runAs(autor) {
            Set<Id> ids = new Set<Id>();
            for (RaizGovernancaService.Revisor r : RaizGovernancaService.revisoresElegiveis(autor.Id)) ids.add(r.id);
            System.assert(ids.contains(revisor.Id), 'aprovador deve aparecer');
            System.assert(!ids.contains(autor.Id), 'autor sem permissao nao aparece');
            System.assertEquals(true, RaizGovernancaService.revisorElegivel(revisor.Id, autor.Id));
            System.assertEquals(false, RaizGovernancaService.revisorElegivel(autor.Id, autor.Id));
            System.assertEquals(false, RaizGovernancaService.revisorElegivel(null, autor.Id));
        }
        // O proprio aprovador, como autor, nao se ve na lista.
        Set<Id> doAprovador = new Set<Id>();
        for (RaizGovernancaService.Revisor r : RaizGovernancaService.revisoresElegiveis(revisor.Id)) doAprovador.add(r.id);
        System.assert(!doAprovador.contains(revisor.Id), 'quem escreve nao aprova');
    }

    @IsTest
    static void avaliacaoListaFaltasEAvisos() {
        User autor = RaizTestData.usuarioRaiz();
        User revisor = RaizTestData.usuarioAprovador();
        System.runAs(autor) {
            RaizGovernancaService.Avaliacao vazia = RaizGovernancaService.avaliarSubmissao(new Business_Rule__c());
            System.assertEquals(false, vazia.apto);
            System.assert(vazia.faltas.contains('Processo crítico'));
            System.assert(vazia.faltas.contains('Título'));
            System.assert(vazia.faltas.contains('Resumo e finalidade'));
            System.assert(vazia.faltas.contains('Etapas operacionais'));
            System.assert(vazia.faltas.contains('Revisor'));
            System.assertEquals(2, vazia.avisos.size(), 'sem prazo + necessario para aprovar');

            Processo_Critico__c p = processo('Aval');
            Business_Rule__c completo = new Business_Rule__c(
                Processo_Critico__c = p.Id,
                Title__c = 'Completo',
                Proposito_Documento__c = '<p>Para que serve</p>',
                Descricao_Demanda__c = '<p>Passo 1</p>',
                Criterios_Aceite__c = '<p>Resultado</p>',
                Cenarios_Teste__c = '<p>Excecao</p>',
                Revisor__c = revisor.Id,
                Prazo_Revisao__c = Date.today().addDays(3)
            );
            RaizGovernancaService.Avaliacao ok = RaizGovernancaService.avaliarSubmissao(completo);
            System.assertEquals(true, ok.apto, String.valueOf(ok.faltas));
            System.assert(ok.avisos.isEmpty(), String.valueOf(ok.avisos));

            completo.Revisor__c = autor.Id;
            System.assert(RaizGovernancaService.avaliarSubmissao(completo).faltas.contains('Revisor diferente do autor'));

            User sem = RaizTestData.usuarioSemAcesso();
            if (sem != null) {
                completo.Revisor__c = sem.Id;
                System.assert(
                    RaizGovernancaService.avaliarSubmissao(completo).faltas.contains('Revisor com permissão de aprovação')
                );
            }
            completo.Descricao_Demanda__c = '<p><br></p>';
            System.assert(RaizGovernancaService.avaliarSubmissao(completo).faltas.contains('Etapas operacionais'), 'HTML vazio conta como vazio');
        }
    }

    @IsTest
    static void falhaNoKanbanNaoDerrubaODocumento() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Business_Rule__c d = doc(processo('Kb').Id, 'Draft');
            RaizGovernancaService.Cartao c = RaizGovernancaService.sincronizarCartao(d.Id);
            System.assertNotEquals(null, c.acao);
            if (c.id == null) {
                System.assertEquals('não atualizado', c.acao);
                System.assert(c.aviso.startsWith('O documento foi salvo'), c.aviso);
            }
            System.assertEquals(1, [SELECT COUNT() FROM Business_Rule__c WHERE Id = :d.Id], 'documento continua salvo');

            Business_Rule__c dep = doc(processo('Dep').Id, 'Depreciada');
            RaizGovernancaService.Cartao semColuna = RaizGovernancaService.sincronizarCartao(dep.Id);
            System.assertEquals('não atualizado', semColuna.acao);
            System.assert(semColuna.aviso.contains('não tem coluna'), semColuna.aviso);
        }
        RaizGovernancaService.Cartao inexistente = RaizGovernancaService.sincronizarCartao(null);
        System.assertEquals('não atualizado', inexistente.acao);
    }

    @IsTest
    static void umCartaoPorDocumentoQueAcompanhaOStatus() {
        // Roda como o usuario do deploy, que normalmente tem o Kanban. Se nao tiver,
        // o servico devolve aviso (comportamento coberto no teste anterior).
        Business_Rule__c d = doc(processo('Mov').Id, 'Draft');
        RaizGovernancaService.Cartao c1 = RaizGovernancaService.sincronizarCartao(d.Id);
        System.debug(LoggingLevel.INFO, 'RAIZ TESTE cartao: ' + c1.acao + ' / ' + c1.aviso);
        if (c1.id == null) return;
        System.assertEquals('criado', c1.acao);
        System.assertEquals('Backlog', c1.etapa);
        System.assertEquals('sem mudança', RaizGovernancaService.sincronizarCartao(d.Id).acao, 'idempotente');

        // Completo e com revisor: em revisao, o cartao vai para a coluna de analise.
        update new Business_Rule__c(
            Id = d.Id,
            Proposito_Documento__c = '<p>P</p>',
            Descricao_Demanda__c = '<p>D</p>',
            Revisor__c = RaizTestData.usuarioAprovador().Id,
            Status__c = 'Em Analise'
        );
        RaizGovernancaService.Cartao c2 = RaizGovernancaService.sincronizarCartao(d.Id);
        System.assertEquals(c1.id, c2.id, 'mesmo cartao');
        System.assertEquals('Em atendimento-Analise TI', c2.etapa);
        System.assertEquals(1, [SELECT COUNT() FROM CRM_Kanban_Task__c WHERE Business_Rule__c = :d.Id], 'um cartao por documento');

        // Bloqueado pela governanca: o cartao volta/fica no Backlog.
        update new Business_Rule__c(Id = d.Id, Governanca_Status__c = 'Bloqueado: falta Revisor');
        System.assertEquals('Backlog', RaizGovernancaService.sincronizarCartao(d.Id).etapa);
    }
}
