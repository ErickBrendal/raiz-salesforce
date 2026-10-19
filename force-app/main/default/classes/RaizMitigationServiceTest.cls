/**
 * RaizMitigationServiceTest — planos e acoes de mitigacao (Onda 3).
 */
@IsTest
private class RaizMitigationServiceTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
    }

    private class Cenario {
        Account conta;
        Processo_Critico__c pontoUnico;   // 1 apto -> Habilitar substituto
        Processo_Critico__c semDado;      // sem aptos -> Levantar informacao
        Processo_Critico__c vencido;      // coberto, registro vencido -> Atualizar
        Processo_Critico__c semRegistro;  // coberto, sem registro -> Registrar
        Processo_Critico__c ok;           // coberto e atualizado -> nada
    }

    private static Cenario montar() {
        Cenario c = new Cenario();
        c.conta = RaizTestData.conta('Mitigacao SA');
        c.pontoUnico = RaizTestData.processo(c.conta.Id, 'Ponto unico', 'Critico', 1, 1000, 10);
        c.semDado = RaizTestData.processo(c.conta.Id, 'Sem dado', 'Alto', null, 100, 2);
        c.vencido = RaizTestData.processo(c.conta.Id, 'Vencido', 'Medio', 3, 100, 2);
        c.vencido.Ultima_Revisao__c = Date.today().addMonths(-10);
        c.semRegistro = RaizTestData.processo(c.conta.Id, 'Sem registro', 'Baixo', 3, 100, 2);
        c.semRegistro.Status_Registro__c = 'Sem registro';
        c.semRegistro.Ultima_Revisao__c = null;
        c.ok = RaizTestData.processo(c.conta.Id, 'Ok', 'Alto', 3, 100, 2);
        insert new List<Processo_Critico__c>{ c.pontoUnico, c.semDado, c.vencido, c.semRegistro, c.ok };
        return c;
    }

    private static Map<Id, RaizMitigationService.Sugestao> porProcesso(RaizMitigationService.Painel p) {
        Map<Id, RaizMitigationService.Sugestao> m = new Map<Id, RaizMitigationService.Sugestao>();
        for (RaizMitigationService.Sugestao s : p.sugestoes) {
            m.put(s.processoId, s);
        }
        return m;
    }

    @IsTest
    static void sugereObjetivoPeloEstadoDoProcesso() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            RaizMitigationService.Painel p = RaizMitigationService.getPainel(c.conta.Id);
            Map<Id, RaizMitigationService.Sugestao> m = porProcesso(p);
            System.assertEquals(4, p.processosSemPlano, 'o processo coberto e atualizado nao precisa de plano');
            System.assertEquals(RaizMitigationService.HABILITAR, m.get(c.pontoUnico.Id).objetivo);
            System.assertEquals(RaizMitigationService.LEVANTAR, m.get(c.semDado.Id).objetivo);
            System.assertEquals('Levantar informação', m.get(c.semDado.Id).objetivoRotulo);
            System.assertEquals(RaizMitigationService.ATUALIZAR, m.get(c.vencido.Id).objetivo);
            System.assertEquals(RaizMitigationService.REGISTRAR, m.get(c.semRegistro.Id).objetivo);
            System.assert(!m.containsKey(c.ok.Id));
            System.assertEquals(c.pontoUnico.Id, p.sugestoes[0].processoId, 'maior score primeiro');
            System.assertEquals(3, p.premissas.size());
            System.assertEquals(0, p.planosAbertos);
        }
    }

    @IsTest
    static void criarPlanoGeraAcoesEFotografaORisco() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Test.startTest();
            Id planoId = RaizMitigationService.criarPlano(c.pontoUnico.Id);
            Test.stopTest();

            Plano_Mitigacao__c pl = [
                SELECT Objetivo__c, Status__c, Score_Inicial__c, Estado_Inicial__c, Data_Alvo__c, Acoes_Total__c, Progresso__c
                FROM Plano_Mitigacao__c
                WHERE Id = :planoId
            ];
            System.assertEquals(RaizMitigationService.HABILITAR, pl.Objetivo__c);
            System.assertEquals(RaizMitigationService.RASCUNHO, pl.Status__c);
            System.assertEquals(12, pl.Score_Inicial__c, 'critico 4 x ponto unico 3 x atualizado 1');
            System.assertEquals(RaizRiskEngine.PONTO_UNICO, pl.Estado_Inicial__c);
            System.assertEquals(Date.today().addDays(RaizMitigationService.PRAZO_PADRAO_DIAS), pl.Data_Alvo__c);
            System.assertEquals(3, pl.Acoes_Total__c);
            System.assertEquals(0, pl.Progresso__c);

            RaizMitigationService.Painel p = RaizMitigationService.getPainel(c.conta.Id);
            System.assertEquals(1, p.planosAbertos);
            System.assertEquals(3, p.processosSemPlano, 'com plano aberto sai das sugestoes');
            RaizMitigationService.PlanoDTO d = p.planos[0];
            System.assertEquals(3, d.acoes.size());
            System.assertEquals('Definir quem será o substituto', d.acoes[0].descricao, 'ordem das acoes');
            System.assertEquals(12, d.scoreAtual);
            System.assertEquals(false, d.podeConcluir);
            System.assertEquals('Rascunho', d.statusRotulo);
        }
    }

    @IsTest
    static void todosOsModelosTemAcoes() {
        for (String o : new List<String>{
            RaizMitigationService.HABILITAR,
            RaizMitigationService.REGISTRAR,
            RaizMitigationService.ATUALIZAR,
            RaizMitigationService.LEVANTAR
        }) {
            System.assert(!RaizMitigationService.modelo(o).isEmpty(), o);
        }
    }

    @IsTest
    static void umPlanoAbertoPorProcessoEProcessoOkRecusado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            RaizMitigationService.criarPlano(c.vencido.Id);
            for (Id alvo : new List<Id>{ c.vencido.Id, c.ok.Id, null }) {
                try {
                    RaizMitigationService.criarPlano(alvo);
                    System.assert(false, 'deveria recusar ' + alvo);
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().length() > 5, e.getMessage());
                }
            }
            System.assertEquals(1, [SELECT COUNT() FROM Plano_Mitigacao__c]);
        }
    }

    @IsTest
    static void cicloCompletoDoPlano() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Id planoId = RaizMitigationService.criarPlano(c.semDado.Id);
            RaizMitigationService.mudarStatusPlano(planoId, RaizMitigationService.EM_EXECUCAO);

            List<Acao_Mitigacao__c> acoes = [SELECT Id FROM Acao_Mitigacao__c WHERE Plano__c = :planoId ORDER BY Ordem__c];
            RaizMitigationService.concluirAcao(acoes[0].Id);
            Acao_Mitigacao__c a0 = [SELECT Status__c, Concluida_Em__c FROM Acao_Mitigacao__c WHERE Id = :acoes[0].Id];
            System.assertEquals('Concluida', a0.Status__c);
            System.assertEquals(Date.today(), a0.Concluida_Em__c, 'gatilho carimba a data');

            // Regra de validacao: nao conclui com acao pendente.
            try {
                RaizMitigationService.mudarStatusPlano(planoId, RaizMitigationService.CONCLUIDO);
                System.assert(false, 'deveria barrar');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Conclua todas as ações'), e.getMessage());
            }
            System.assertEquals(50, RaizMitigationService.getPainel(c.conta.Id).planos[0].progresso, '1 de 2');

            RaizMitigationService.concluirAcao(acoes[1].Id);
            RaizMitigationService.mudarStatusPlano(planoId, RaizMitigationService.CONCLUIDO);
            System.assertEquals(
                RaizMitigationService.CONCLUIDO,
                [SELECT Status__c FROM Plano_Mitigacao__c WHERE Id = :planoId].Status__c
            );

            // Concluir o plano NAO cria habilitacao: o processo segue sem informacao.
            Processo_Critico__c p = [SELECT Estado_Cobertura__c FROM Processo_Critico__c WHERE Id = :c.semDado.Id];
            System.assertEquals(RaizRiskEngine.INSUFICIENTE, p.Estado_Cobertura__c);
            System.assertEquals(0, [SELECT COUNT() FROM Habilitacao__c]);
            // Plano concluido volta a liberar sugestao para o processo.
            RaizMitigationService.Painel pn = RaizMitigationService.getPainel(c.conta.Id);
            System.assert(porProcesso(pn).containsKey(c.semDado.Id));
            // Um novo plano aberto impede reabrir o antigo.
            RaizMitigationService.criarPlano(c.semDado.Id);
            try {
                RaizMitigationService.mudarStatusPlano(planoId, RaizMitigationService.EM_EXECUCAO);
                System.assert(false, 'deveria impedir dois planos abertos');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('outro plano aberto'), e.getMessage());
            }
        }
    }

    @IsTest
    static void reabrirAcaoLimpaDataEStatusInvalidoERecusado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Id planoId = RaizMitigationService.criarPlano(c.semRegistro.Id);
            Acao_Mitigacao__c a = [SELECT Id FROM Acao_Mitigacao__c WHERE Plano__c = :planoId LIMIT 1];
            RaizMitigationService.concluirAcao(a.Id);
            update new Acao_Mitigacao__c(Id = a.Id, Status__c = 'Em andamento');
            System.assertEquals(null, [SELECT Concluida_Em__c FROM Acao_Mitigacao__c WHERE Id = :a.Id].Concluida_Em__c);
            try {
                RaizMitigationService.mudarStatusPlano(planoId, 'Rascunho');
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('inválido'), e.getMessage());
            }
            RaizMitigationService.mudarStatusPlano(planoId, RaizMitigationService.CANCELADO);
            System.assertEquals(0, RaizMitigationService.getPainel(null).planosAbertos);
        }
    }

    @IsTest
    static void atrasoEContado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Id planoId = RaizMitigationService.criarPlano(c.pontoUnico.Id);
            update new Plano_Mitigacao__c(Id = planoId, Data_Alvo__c = Date.today().addDays(-1));
            update new Acao_Mitigacao__c(
                Id = [SELECT Id FROM Acao_Mitigacao__c WHERE Plano__c = :planoId LIMIT 1].Id,
                Prazo__c = Date.today().addDays(-2)
            );
            RaizMitigationService.Painel p = RaizMitigationService.getPainel(null);
            System.assertEquals(1, p.planosAtrasados);
            System.assertEquals(true, p.planos[0].atrasado);
            Boolean algumaAtrasada = false;
            for (RaizMitigationService.AcaoDTO x : p.planos[0].acoes) {
                if (x.atrasada) algumaAtrasada = true;
            }
            System.assert(algumaAtrasada);
        }
    }

    @IsTest
    static void usuarioSemPermissaoRecebeMensagemClara() {
        User sem = RaizTestData.usuarioSemAcesso();
        Id procId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            procId = montar().pontoUnico.Id;
        }
        if (sem == null) {
            return;
        }
        System.runAs(sem) {
            Boolean falhou = false;
            try {
                RaizMitigationService.getPainel(null);
            } catch (AuraHandledException e) {
                falhou = true;
            }
            try {
                RaizMitigationService.criarPlano(procId);
            } catch (AuraHandledException e) {
                falhou = true;
            }
            try {
                RaizMitigationService.concluirAcao(procId);
            } catch (AuraHandledException e) {
                falhou = true;
            }
            System.assert(falhou || Schema.SObjectType.Plano_Mitigacao__c.isCreateable());
        }
    }
}
