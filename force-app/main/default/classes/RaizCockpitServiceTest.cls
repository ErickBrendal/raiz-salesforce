/**
 * RaizCockpitServiceTest
 * ---------------------------------------------------------------------------
 * Os testes aqui nao existem para atingir 75% de cobertura. Existem para
 * travar as quatro regras de negocio que, se quebrarem, fazem o cockpit
 * mentir com aparencia de correto:
 *
 *   1. Ponto unico de falha e Pessoas_Aptas <= 1  (nao < 1, nao <= 2)
 *   2. Exposicao financeira SO conta onde ha ponto unico de falha
 *   3. Um registro vencido NAO conta como atualizado
 *   4. Zero processo devolve zero com ressalva — nunca verde silencioso
 *
 * A regra 4 e a mais importante: painel que mostra 100% de cobertura porque
 * nao ha nada mapeado e o defeito mais caro que um dashboard pode ter.
 */
@IsTest
private class RaizCockpitServiceTest {

    private static Account conta;

    private static Processo_Critico__c novo(String nome, String crit, Integer aptos,
                                            String statusReg, Date ultRev,
                                            Decimal impactoHora, Integer horas) {
        return new Processo_Critico__c(
            Name = nome,
            Conta__c = conta.Id,
            Area__c = 'Comercial',
            Criticidade__c = crit,
            Pessoas_Aptas__c = aptos,
            Status_Registro__c = statusReg,
            Ultima_Revisao__c = ultRev,
            Validade_Meses__c = 6,
            Impacto_Hora__c = impactoHora,
            Horas_Para_Restabelecer__c = horas,
            Sistema_Origem__c = 'So na cabeca da pessoa',
            Dono__c = UserInfo.getUserId()
        );
    }

    // Onda 1: os testes rodam como usuario com o permission set (USER_MODE
    // falha sem FLS nos campos novos). A conta e criada pelo proprio usuario.
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
    }

    private static void carregarConta() {
        List<Account> as1 = [SELECT Id FROM Account WHERE Name = 'Industria Demo RAIZ' LIMIT 1];
        conta = as1.isEmpty() ? RaizTestData.conta('Industria Demo RAIZ') : as1[0];
    }

    @IsTest
    static void pontoUnicoDeFalhaEAteUmaPessoa() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert new List<Processo_Critico__c>{
                novo('Uma pessoa',   'Critico', 1, 'Registrado', Date.today(), 500, 10),
                novo('Zero pessoas', 'Critico', 0, 'Registrado', Date.today(), 500, 10),
                novo('Duas pessoas', 'Critico', 2, 'Registrado', Date.today(), 500, 10)
            };

            Map<String, Processo_Critico__c> m = new Map<String, Processo_Critico__c>();
            for (Processo_Critico__c p : [
                SELECT Name, Ponto_Unico_de_Falha__c, Exposicao_Financeira__c
                FROM Processo_Critico__c WHERE Conta__c = :conta.Id
            ]) { m.put(p.Name, p); }

            System.assertEquals(true,  m.get('Uma pessoa').Ponto_Unico_de_Falha__c,   '1 apto deve ser ponto unico');
            System.assertEquals(true,  m.get('Zero pessoas').Ponto_Unico_de_Falha__c, '0 apto deve ser ponto unico');
            System.assertEquals(false, m.get('Duas pessoas').Ponto_Unico_de_Falha__c, '2 aptos NAO e ponto unico');

            // Regra 2: exposicao so existe onde ha ponto unico.
            System.assertEquals(5000, m.get('Uma pessoa').Exposicao_Financeira__c,   '500 x 10');
            System.assertEquals(0,    m.get('Duas pessoas').Exposicao_Financeira__c, 'sem ponto unico, sem exposicao');
        }
    }

    @IsTest
    static void registroVencidoNaoContaComoAtualizado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            // Revisado ha 10 meses com validade de 6: vencido.
            insert novo('Vencido', 'Alto', 3, 'Registrado', Date.today().addMonths(-10), 100, 4);
            Processo_Critico__c p = [
                SELECT Atualizado__c, Dias_Para_Vencer__c
                FROM Processo_Critico__c WHERE Name = 'Vencido' LIMIT 1
            ];
            System.assertEquals(false, p.Atualizado__c, 'documento vencido nao pode contar como atualizado');
            System.assert(p.Dias_Para_Vencer__c < 0, 'dias para vencer deve ser negativo');
        }
    }

    @IsTest
    static void cockpitCalculaOsIndicadores() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert new List<Processo_Critico__c>{
                novo('Critico exposto', 'Critico', 1, 'Sem registro',  null,               1000, 20),
                novo('Critico coberto', 'Critico', 3, 'Registrado',    Date.today(),        500, 5),
                novo('Alto exposto',    'Alto',    1, 'Desatualizado', Date.today().addMonths(-9), 200, 8)
            };

            Test.startTest();
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            Test.stopTest();

            System.assertEquals(3, c.totalProcessos);

            Map<String, RaizCockpitService.Indicador> ind = new Map<String, RaizCockpitService.Indicador>();
            for (RaizCockpitService.Indicador i : c.indicadores) ind.put(i.chave, i);

            // 2 processos com 1 apto -> indice de dependencia = 2
            System.assertEquals(2, ind.get('dependencia').valor, 'dois pontos unicos de falha');

            // Exposicao: (1000x20) + (200x8) = 21.600. O coberto nao entra.
            System.assertEquals(21600, ind.get('exposicao').valor, 'so os pontos unicos entram na exposicao');
            // Formato fixo pt-BR, independente do locale de quem roda o teste.
            System.assertEquals('R$ 21.600', ind.get('exposicao').valorFormatado);

            // Cobertura: 3 criticos/altos, 1 com registro atualizado E dono -> 33%
            System.assertEquals(33, ind.get('cobertura').valor, 'um de tres cobertos');

            // O tom do indice de dependencia usa CONTAGEM ABSOLUTA, nao proporcao:
            // 0 = bom, 1 a 3 = atencao, 4+ = critico. Com 2 pontos unicos, 'atencao'
            // e a resposta correta — a assercao anterior esperava 'critico' e era
            // ELA que estava errada, nao o codigo.
            //
            // A escolha por contagem absoluta e deliberada: uma empresa com 4
            // processos criticos dependentes de uma pessoa esta em situacao critica
            // tendo 10 ou 300 processos mapeados. Proporcao esconderia isso.
            System.assertEquals('atencao', ind.get('dependencia').tom,
                'dois pontos unicos de falha devem dar tom de atencao');

            // O limiar critico so dispara a partir do quarto.
            insert new List<Processo_Critico__c>{
                novo('Quarto exposto', 'Critico', 1, 'Sem registro', null, 100, 2),
                novo('Quinto exposto', 'Alto',    1, 'Sem registro', null, 100, 2)
            };
            RaizCockpitService.Cockpit c2 = RaizCockpitService.getCockpit(conta.Id);
            for (RaizCockpitService.Indicador i : c2.indicadores) {
                if (i.chave == 'dependencia') {
                    System.assertEquals(4, i.valor, 'quatro pontos unicos agora');
                    System.assertEquals('critico', i.tom, 'a partir do quarto, critico');
                }
            }
        }
    }

    @IsTest
    static void semDadoNaoMostraVerde() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            Test.startTest();
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            Test.stopTest();

            System.assertEquals(0, c.totalProcessos);
            System.assert(!c.ressalvas.isEmpty(),
                'sem processo mapeado, o painel TEM de declarar que o zero e por ausencia de dado');

            for (RaizCockpitService.Indicador i : c.indicadores) {
                if (i.chave == 'cobertura' || i.chave == 'atualidade') {
                    System.assertEquals(0, i.valor, i.chave + ' sem dado deve ser 0, nunca 100');
                }
            }
        }
    }

    @IsTest
    static void simuladorRespondeComNomeENumero() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert new List<Processo_Critico__c>{
                novo('Fechamento fiscal', 'Critico', 1, 'Sem registro', null, 800, 16),
                novo('Conciliacao',       'Alto',    1, 'Sem registro', null, 300, 8),
                novo('Apuracao ICMS',     'Critico', 1, 'Sem registro', null, 200, 10),
                novo('Rotina coberta',    'Medio',   4, 'Registrado', Date.today(), 100, 2)
            };

            Test.startTest();
            RaizCockpitService.ResultadoSimulacao r =
                RaizCockpitService.simularSaida(conta.Id, UserInfo.getUserId());
            Test.stopTest();

            System.assertEquals(3, r.processosParados, 'so os de ponto unico param');
            System.assertEquals(17200, r.exposicao, '(800x16)+(300x8)+(200x10)');
            System.assertEquals(34, r.horasParaRestabelecer, '16+8+10');
            // Com 3 ou mais processos parados o veredito precisa nomear o produto
            // que resolve — vender e parte do trabalho do painel.
            System.assert(r.veredito.contains('Sprint de Sucessao'),
                'veredito deveria indicar o P5, veio: ' + r.veredito);
            System.assertEquals(3, r.processos.size());
        }
    }

    @IsTest
    static void listasDeApoioRespondem() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert novo('Processo A', 'Alto', 1, 'Registrado', Date.today(), 100, 3);

            Test.startTest();
            List<Map<String,String>> clientes = RaizCockpitService.getClientes();
            List<Map<String,String>> donos    = RaizCockpitService.getDonos(conta.Id);
            RaizCockpitService.Cockpit geral  = RaizCockpitService.getCockpit(null);
            Test.stopTest();

            System.assert(clientes.size() >= 2, 'deve ter a opcao "todos" mais a conta');
            System.assertEquals('Todos os clientes', clientes[0].get('label'));
            System.assert(!donos.isEmpty(), 'o dono do processo deve aparecer na lista');
            System.assertEquals('Todos os clientes', geral.cliente);
        }
    }

    // ------------------------------------------------------------- Onda 1
    @IsTest
    static void semInformacaoNaoViraVerdeNemPontoUnico() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert novo('Sem dado de aptos', 'Medio', null, 'Registrado', Date.today(), 100, 4);

            Test.startTest();
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            Test.stopTest();

            System.assertEquals(1, c.informacaoInsuficiente, 'processo sem aptos e sem habilitacao = informacao insuficiente');
            System.assertEquals(RaizRiskEngine.INSUFICIENTE, c.topRiscos[0].estadoCobertura);
            System.assertEquals(null, c.topRiscos[0].pessoasAptas, 'sem dado fica nulo, nunca zero');
            System.assertEquals(false, c.topRiscos[0].pontoUnico, 'insuficiente nao e ponto unico');
            for (RaizCockpitService.Indicador i : c.indicadores) {
                if (i.chave == 'dependencia' || i.chave == 'exposicao') {
                    System.assertNotEquals('bom', i.tom, i.chave + ' nao pode ficar verde com informacao insuficiente');
                }
            }
            Boolean temRessalva = false;
            for (String r : c.ressalvas) {
                if (r.contains('sem informação de pessoas aptas')) temRessalva = true;
            }
            System.assert(temRessalva, 'deve declarar a falta de informacao');
        }
    }

    @IsTest
    static void exposicaoIncompletaEPremissaSaoDeclaradas() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert new List<Processo_Critico__c>{
                novo('Ponto unico sem custo', 'Critico', 1, 'Sem registro', null, null, 10),
                novo('Ponto unico com custo', 'Critico', 1, 'Sem registro', null, 100, 10)
            };
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            System.assertEquals(1, c.exposicaoIncompleta);
            String todas = String.join(c.ressalvas, ' | ');
            System.assert(todas.contains('subestimada'), todas);
            System.assert(todas.contains('independentes'), 'premissa de sobreposicao deve aparecer: ' + todas);
            System.assertEquals(2, c.coberturaDeclarada, 'aptos so declarados devem ser sinalizados');
        }
    }

    // ------------------------------------------------------------- Onda 3
    @IsTest
    static void concentracaoUsaHabilitacaoENaoODono() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            Processo_Critico__c so = novo('So a Ana', 'Critico', null, 'Registrado', Date.today(), 1000, 10);
            Processo_Critico__c dupla = novo('Ana e Bia', 'Alto', null, 'Registrado', Date.today(), 500, 4);
            Processo_Critico__c ninguem = novo('Ninguem apto', 'Medio', 0, 'Registrado', Date.today(), 100, 2);
            insert new List<Processo_Critico__c>{ so, dupla, ninguem };
            Profissional__c ana = RaizTestData.profissional(conta.Id, 'Ana Conc');
            Profissional__c bia = RaizTestData.profissional(conta.Id, 'Bia Conc');
            insert new List<Profissional__c>{ ana, bia };
            insert new List<Habilitacao__c>{
                RaizTestData.habilitacao(so.Id, ana.Id, 'Apto', null),
                RaizTestData.habilitacao(dupla.Id, ana.Id, 'Apto', null),
                RaizTestData.habilitacao(dupla.Id, bia.Id, 'Apto', null)
            };

            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);

            System.assertEquals(2, c.pessoasChave.size(), 'Ana e Bia; o dono (usuario) nao entra');
            RaizCockpitService.PessoaChave primeira = c.pessoasChave[0];
            System.assertEquals('Ana Conc', primeira.nome);
            System.assertEquals(1, primeira.processosSozinho);
            System.assertEquals(2, primeira.processosTotal);
            System.assertEquals(10000, primeira.exposicao);
            System.assertEquals(0, c.pessoasChave[1].processosSozinho);
            String todas = String.join(c.ressalvas, ' | ');
            System.assert(todas.contains('1 ponto único não aparece'), todas);
        }
    }

    @IsTest
    static void rotulosComAcentoEConcordancia() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            Processo_Critico__c p = novo('Rotulo', 'Critico', null, 'Registrado', Date.today(), 10, 1);
            p.Area__c = 'Producao';
            insert p;
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            RaizCockpitService.LinhaRisco l = c.topRiscos[0];
            System.assertEquals('Produção', l.areaRotulo);
            System.assertEquals('Crítico', l.criticidadeRotulo);
            System.assertEquals('—', l.aptosTexto, 'sem informacao mostra traco, nao zero');
            Boolean achou = false;
            for (RaizCockpitService.Fatia f : c.matrizRisco) {
                if (f.rotulo == 'Alto') {
                    achou = true;
                    System.assertEquals('Alto', f.rotuloExibicao);
                }
            }
            System.assert(achou, 'critico 4 x insuficiente 3 x atualizado 1 = 12 -> Alto');
            System.assertEquals('1 processo', RaizCockpitService.qtd(1, 'processo', 'processos'));
            System.assertEquals('2 processos', RaizCockpitService.qtd(2, 'processo', 'processos'));
        }
    }

    // ------------------------------------------------------------- Onda 4
    @IsTest
    static void quatroEstadosSempreAparecemNaOrdem() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            insert novo('Coberto', 'Medio', 3, 'Registrado', Date.today(), 10, 1);
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            System.assertEquals(4, c.estadosCobertura.size());
            System.assertEquals('Sem cobertura', c.estadosCobertura[0].rotuloExibicao);
            System.assertEquals('Ponto único', c.estadosCobertura[1].rotuloExibicao);
            System.assertEquals('Informação insuficiente', c.estadosCobertura[2].rotuloExibicao);
            System.assertEquals('Coberto', c.estadosCobertura[3].rotuloExibicao);
            System.assertEquals(1, c.estadosCobertura[3].quantidade);
            System.assertEquals(100, c.estadosCobertura[3].percentual);
            System.assertEquals(0, c.estadosCobertura[0].quantidade);
            System.assertEquals(false, c.semPermissao);
        }
    }

    @IsTest
    static void reducaoDeRiscoDosPlanos() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            carregarConta();
            Processo_Critico__c pu = novo('Ponto unico com plano', 'Critico', 1, 'Registrado', Date.today(), 100, 2);
            Processo_Critico__c pu2 = novo('Ponto unico sem plano', 'Alto', 1, 'Registrado', Date.today(), 100, 2);
            insert new List<Processo_Critico__c>{ pu, pu2 };
            // Plano nasceu com score 24 (fotografia antiga); hoje o processo esta em 12.
            insert new Plano_Mitigacao__c(Name = 'Plano', Processo__c = pu.Id, Objetivo__c = 'Habilitar substituto',
                Status__c = 'Em execucao', Score_Inicial__c = 24, Data_Alvo__c = Date.today().addDays(-1));
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(conta.Id);
            System.assertEquals(1, c.planosAbertos);
            System.assertEquals(1, c.planosAtrasados);
            System.assertEquals(1, c.processosComPlano);
            System.assertEquals(24, c.scoreInicialPlanos);
            System.assertEquals(12, c.scoreAtualPlanos, 'critico 4 x ponto unico 3 x atualizado 1');
            System.assertEquals(1, c.pontosUnicosSemPlano);
        }
    }

    @IsTest
    static void semPermissaoESinalizado() {
        User sem = RaizTestData.usuarioSemAcesso();
        if (sem == null) return;
        System.runAs(sem) {
            RaizCockpitService.Cockpit c = RaizCockpitService.getCockpit(null);
            System.assert(c.semPermissao || Schema.SObjectType.Processo_Critico__c.isAccessible(),
                'sem permission set o cockpit avisa em vez de mostrar zeros');
        }
    }
}
