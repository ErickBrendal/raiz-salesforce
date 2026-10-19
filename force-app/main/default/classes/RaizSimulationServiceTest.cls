/**
 * RaizSimulationServiceTest — simulador de ausencia v2 (Onda 2).
 *
 * Cenario: Ana e titular de tres processos.
 *   Fechamento  — so Ana                 -> PARA (1000 x 16 = 16.000)
 *   Apuracao    — Ana + Bruno            -> FICA FRAGIL
 *   Conciliacao — Ana + Bruno + Carla    -> CONTINUA COBERTO
 *   Inventario  — so Bruno               -> fora da simulacao da Ana
 */
@IsTest
private class RaizSimulationServiceTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
    }

    private class Cenario {
        Account conta;
        Profissional__c ana;
        Profissional__c bruno;
        Profissional__c carla;
    }

    private static Cenario montar() {
        Cenario c = new Cenario();
        c.conta = RaizTestData.conta('Industria Simulacao');
        c.ana = RaizTestData.profissional(c.conta.Id, 'Ana Teste');
        c.bruno = RaizTestData.profissional(c.conta.Id, 'Bruno Teste');
        c.carla = RaizTestData.profissional(c.conta.Id, 'Carla Teste');
        insert new List<Profissional__c>{ c.ana, c.bruno, c.carla };

        Processo_Critico__c fech = RaizTestData.processo(c.conta.Id, 'Fechamento', 'Critico', null, 1000, 16);
        Processo_Critico__c apur = RaizTestData.processo(c.conta.Id, 'Apuracao', 'Alto', null, 500, 8);
        Processo_Critico__c conc = RaizTestData.processo(c.conta.Id, 'Conciliacao', 'Medio', null, 100, 4);
        Processo_Critico__c inv = RaizTestData.processo(c.conta.Id, 'Inventario', 'Alto', null, 300, 10);
        insert new List<Processo_Critico__c>{ fech, apur, conc, inv };

        Date val = Date.today().addMonths(6);
        insert new List<Habilitacao__c>{
            RaizTestData.habilitacao(fech.Id, c.ana.Id, 'Apto', val),
            RaizTestData.habilitacao(fech.Id, c.carla.Id, 'Em treinamento', val),
            RaizTestData.habilitacao(apur.Id, c.ana.Id, 'Apto', val),
            RaizTestData.habilitacao(apur.Id, c.bruno.Id, 'Apto', val),
            RaizTestData.habilitacao(conc.Id, c.ana.Id, 'Apto', null),
            RaizTestData.habilitacao(conc.Id, c.bruno.Id, 'Apto', val),
            RaizTestData.habilitacao(conc.Id, c.carla.Id, 'Apto', val),
            RaizTestData.habilitacao(inv.Id, c.bruno.Id, 'Apto', val)
        };
        return c;
    }

    @IsTest
    static void ausenciaSeparaParaFragilEContinua() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Test.startTest();
            RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(c.conta.Id, c.ana.Id);
            Test.stopTest();

            System.assertEquals('Ana Teste', r.pessoa);
            System.assertEquals(3, r.processosAvaliados, 'Inventario nao e da Ana');
            System.assertEquals(1, r.param);
            System.assertEquals(1, r.ficamFrageis);
            System.assertEquals(1, r.continuam);
            System.assert(r.exposicao == 16000, 'so o que para entra: ' + r.exposicao);
            System.assert(r.horasParaRestabelecer == 16, 'horas: ' + r.horasParaRestabelecer);

            RaizSimulationService.LinhaSimulacao primeira = r.linhas[0];
            System.assertEquals('Fechamento', primeira.processo, 'o que para vem primeiro');
            System.assertEquals(RaizSimulationService.PARA, primeira.efeito);
            System.assertEquals('Ninguém', primeira.substitutos, 'em treinamento nao substitui');
            System.assertEquals('Fiscal', primeira.areaRotulo);
            System.assertEquals('Crítico', primeira.criticidadeRotulo);
            System.assertEquals(RaizSimulationService.FRAGIL, r.linhas[1].efeito);
            System.assertEquals('Bruno Teste', r.linhas[1].substitutos);
            System.assertEquals(RaizSimulationService.CONTINUA, r.linhas[2].efeito);
            System.assertEquals('Bruno Teste, Carla Teste', r.linhas[2].substitutos);
            System.assert(r.veredito.contains('1 processo para e 1 fica frágil'), r.veredito);
            System.assertEquals(RaizSimulationService.PREMISSAS.size(), r.premissas.size());
        }
    }

    @IsTest
    static void substitutoComHabilitacaoVencidaNaoCobre() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            // Bruno vence na Apuracao: sem ele, Ana vira a unica e a ausencia dela PARA o processo.
            Habilitacao__c hb = [
                SELECT Id
                FROM Habilitacao__c
                WHERE Profissional__c = :c.bruno.Id AND Processo__r.Name = 'Apuracao'
            ];
            hb.Valida_Ate__c = Date.today().addDays(-1);
            update hb;
            RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(c.conta.Id, c.ana.Id);
            System.assertEquals(2, r.param);
            System.assert(r.exposicao == 16000 + 4000, 'fechamento + apuracao: ' + r.exposicao);
        }
    }

    @IsTest
    static void simulacaoNaoGravaNada() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            Map<Id, Datetime> antesP = new Map<Id, Datetime>();
            for (Processo_Critico__c p : [SELECT Id, SystemModstamp FROM Processo_Critico__c]) {
                antesP.put(p.Id, p.SystemModstamp);
            }
            Map<Id, Datetime> antesH = new Map<Id, Datetime>();
            for (Habilitacao__c h : [SELECT Id, SystemModstamp FROM Habilitacao__c]) {
                antesH.put(h.Id, h.SystemModstamp);
            }
            Integer dmlAntes = Limits.getDmlStatements();
            Integer linhasAntes = Limits.getDmlRows();

            RaizSimulationService.simularAusencia(c.conta.Id, c.ana.Id);
            RaizSimulationService.simularAusencia(null, c.bruno.Id);
            RaizSimulationService.getProfissionais(c.conta.Id);
            RaizSimulationService.getProfissionais(null);

            System.assertEquals(dmlAntes, Limits.getDmlStatements(), 'simulador nao pode executar DML');
            System.assertEquals(linhasAntes, Limits.getDmlRows());
            for (Processo_Critico__c p : [SELECT Id, SystemModstamp FROM Processo_Critico__c]) {
                System.assertEquals(antesP.get(p.Id), p.SystemModstamp, 'processo alterado');
            }
            for (Habilitacao__c h : [SELECT Id, SystemModstamp FROM Habilitacao__c]) {
                System.assertEquals(antesH.get(h.Id), h.SystemModstamp, 'habilitacao alterada');
            }
            System.assertEquals(antesP.size(), [SELECT COUNT() FROM Processo_Critico__c]);
            System.assertEquals(antesH.size(), [SELECT COUNT() FROM Habilitacao__c]);
        }
    }

    @IsTest
    static void listaDeProfissionaisOrdenaPorConcentracao() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            List<RaizSimulationService.Opcao> ops = RaizSimulationService.getProfissionais(c.conta.Id);
            System.assertEquals(3, ops.size());
            // Ana 3 e Bruno 3 empatam; desempate por nome.
            System.assertEquals(c.ana.Id, ops[0].value);
            System.assertEquals(3, ops[0].habilitacoes);
            System.assert(ops[0].label.contains('3 habilitações'), ops[0].label);
            System.assertEquals(c.carla.Id, ops[2].value, 'Carla tem 1 Apto (o treinamento nao conta)');
        }
    }

    @IsTest
    static void semHabilitacaoNaoAfirmaQueNadaPara() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('Vazia');
            Profissional__c p = RaizTestData.profissional(a.Id, 'Sem Registro');
            insert p;
            RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(a.Id, p.Id);
            System.assertEquals(0, r.processosAvaliados);
            System.assert(r.veredito.contains('não dá para afirmar'), r.veredito);
            System.assert(!r.ressalvas.isEmpty(), 'zero por falta de evidencia tem de ser declarado');
        }
    }

    @IsTest
    static void vereditosCobremTodasAsFaixas() {
        RaizSimulationService.Resultado r = new RaizSimulationService.Resultado();
        r.processosAvaliados = 4;
        r.continuam = 4;
        System.assert(RaizSimulationService.veredito(r).startsWith('Nada para.'));
        r.ficamFrageis = 2;
        System.assert(RaizSimulationService.veredito(r).contains('passam a depender'));
        r.param = 3;
        r.horasParaRestabelecer = 40;
        System.assert(RaizSimulationService.veredito(r).startsWith('Concentração crítica'));
        r.param = 1;
        System.assert(RaizSimulationService.veredito(r).startsWith('Exposição contida'));
    }

    @IsTest
    static void exposicaoIncompletaGeraRessalva() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('Incompleta');
            Profissional__c p = RaizTestData.profissional(a.Id, 'Solo');
            insert p;
            Processo_Critico__c pr = RaizTestData.processo(a.Id, 'Sem custo', 'Critico', null, null, 8);
            insert pr;
            insert RaizTestData.habilitacao(pr.Id, p.Id, 'Apto', null);
            RaizSimulationService.Resultado r = RaizSimulationService.simularAusencia(a.Id, p.Id);
            System.assertEquals(1, r.param);
            System.assertEquals(1, r.exposicaoIncompleta);
            System.assertEquals(false, r.linhas[0].exposicaoCompleta);
            System.assert(String.join(r.ressalvas, ' ').contains('subestimada'));
        }
    }

    @IsTest
    static void entradaInvalidaEErroAmigavel() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            try {
                RaizSimulationService.simularAusencia(null, null);
                System.assert(false, 'deveria exigir profissional');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Escolha'), e.getMessage());
            }
            Account a = RaizTestData.conta('Apagado');
            Profissional__c p = RaizTestData.profissional(a.Id, 'Temporario');
            insert p;
            Id idFantasma = p.Id;
            delete p;
            try {
                RaizSimulationService.simularAusencia(null, idFantasma);
                System.assert(false, 'deveria falhar');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('não encontrado'), e.getMessage());
            }
        }
    }

    @IsTest
    static void usuarioSemPermissaoRecebeMensagemClara() {
        User sem = RaizTestData.usuarioSemAcesso();
        Id profId;
        System.runAs(RaizTestData.usuarioRaiz()) {
            Cenario c = montar();
            profId = c.ana.Id;
        }
        if (sem == null) {
            System.assert(true, 'org sem perfil disponivel para o usuario sem acesso');
            return;
        }
        System.runAs(sem) {
            Boolean falhou = false;
            try {
                RaizSimulationService.getProfissionais(null);
            } catch (AuraHandledException e) {
                falhou = true;
                System.assert(e.getMessage().length() > 0);
            }
            try {
                RaizSimulationService.simularAusencia(null, profId);
            } catch (AuraHandledException e) {
                falhou = true;
            }
            // Se o perfil padrao da org ja der acesso ao objeto, nao ha o que negar.
            System.assert(
                falhou || Schema.SObjectType.Habilitacao__c.isAccessible(),
                'sem permission set o simulador falha com mensagem, nao com tela vazia'
            );
        }
    }

    @IsTest
    static void concordanciaNoVeredito() {
        RaizSimulationService.Resultado r = new RaizSimulationService.Resultado();
        r.processosAvaliados = 1;
        r.continuam = 1;
        System.assertEquals('Nada para. O processo continua com ao menos duas pessoas aptas.', RaizSimulationService.veredito(r));
        r.ficamFrageis = 1;
        System.assert(RaizSimulationService.veredito(r).contains('1 processo passa a depender'), RaizSimulationService.veredito(r));
        r.param = 2;
        r.ficamFrageis = 0;
        r.horasParaRestabelecer = 10;
        String v = RaizSimulationService.veredito(r);
        System.assert(v.contains('2 processos param.'), v);
        System.assert(!v.contains('(s)'), 'sem plural generico: ' + v);
        System.assertEquals('1 habilitação', RaizSimulationService.qtd(1, 'habilitação', 'habilitações'));
    }
}
