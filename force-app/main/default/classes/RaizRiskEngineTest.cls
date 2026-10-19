/**
 * RaizRiskEngineTest — os 14 cenarios do motor de risco (Onda 1).
 *
 *  C01  0 aptos com habilitacao registrada      -> Sem cobertura, ponto unico
 *  C02  1 apto                                   -> Ponto unico
 *  C03  2 aptos                                  -> Coberto, sem exposicao
 *  C04  sem habilitacao e sem declarado          -> Informacao insuficiente (nunca verde)
 *  C05  sem habilitacao, declarado 3             -> usa o declarado (fonte Declarado)
 *  C06  habilitacao prevalece sobre o declarado  -> declarado 3, evidenciado 1 = ponto unico
 *  C07  "Em treinamento" nao conta como apto
 *  C08  validade passada na gravacao             -> vira Vencida e nao conta
 *  C09  validade expira depois (job diario)      -> job marca Vencida, contagem cai
 *  C10  exposicao so em ponto unico (impacto x horas)
 *  C11  ponto unico sem impacto/hora             -> Exposicao_Completa = false
 *  C12  registro vencido nao e atualizado        -> score dobra
 *  C13  mesma pessoa duas vezes no processo      -> bloqueado (Chave_Par__c unica)
 *  C14  contrato: formula do objeto == motor Apex, em todas as combinacoes
 *  (extra) profissional desativado -> habilitacoes Apto viram Suspensa
 */
@IsTest
private class RaizRiskEngineTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
    }

    private static Processo_Critico__c ler(Id id) {
        return [
            SELECT
                Id,
                Name,
                Criticidade__c,
                Impacto_Hora__c,
                Horas_Para_Restabelecer__c,
                Atualizado__c,
                Habilitacoes_Registradas__c,
                Aptos_Habilitados__c,
                Aptos_Efetivos__c,
                Fonte_Cobertura__c,
                Estado_Cobertura__c,
                Ponto_Unico_de_Falha__c,
                Exposicao_Financeira__c,
                Exposicao_Completa__c,
                Risco_Score__c,
                Farol__c
            FROM Processo_Critico__c
            WHERE Id = :id
        ];
    }

    private static Integer efetivos(Processo_Critico__c p) {
        return p.Aptos_Efetivos__c == null ? null : p.Aptos_Efetivos__c.intValue();
    }

    /** Cria processo + N profissionais; devolve o processo. */
    private static Processo_Critico__c montar(String nome, Integer declarado, List<String> statusPorPessoa) {
        Account a = RaizTestData.conta('Conta ' + nome);
        Processo_Critico__c p = RaizTestData.processo(a.Id, nome, 'Critico', declarado, 1000, 8);
        insert p;
        List<Profissional__c> pros = new List<Profissional__c>();
        for (Integer i = 0; i < statusPorPessoa.size(); i++) {
            pros.add(RaizTestData.profissional(a.Id, nome + ' pessoa ' + i));
        }
        insert pros;
        List<Habilitacao__c> habs = new List<Habilitacao__c>();
        for (Integer i = 0; i < statusPorPessoa.size(); i++) {
            habs.add(RaizTestData.habilitacao(p.Id, pros[i].Id, statusPorPessoa[i], Date.today().addMonths(6)));
        }
        insert habs;
        return ler(p.Id);
    }

    @IsTest
    static void c01ZeroAptosComHabilitacaoESemCobertura() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C01', 2, new List<String>{ 'Em treinamento' });
            System.assertEquals(0, efetivos(p));
            System.assertEquals(RaizRiskEngine.SEM_COBERTURA, p.Estado_Cobertura__c);
            System.assertEquals(true, p.Ponto_Unico_de_Falha__c, '0 apto e ponto unico (regra 1)');
        }
    }

    @IsTest
    static void c02UmAptoEPontoUnico() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C02', null, new List<String>{ 'Apto' });
            System.assertEquals(1, efetivos(p));
            System.assertEquals(RaizRiskEngine.PONTO_UNICO, p.Estado_Cobertura__c);
            System.assertEquals(true, p.Ponto_Unico_de_Falha__c);
        }
    }

    @IsTest
    static void c03DoisAptosECobertoSemExposicao() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C03', null, new List<String>{ 'Apto', 'Apto' });
            System.assertEquals(RaizRiskEngine.COBERTO, p.Estado_Cobertura__c);
            System.assertEquals(false, p.Ponto_Unico_de_Falha__c);
            System.assertEquals(0, p.Exposicao_Financeira__c, 'coberto nao tem exposicao (regra 2)');
        }
    }

    @IsTest
    static void c04SemDadoEInformacaoInsuficienteENuncaVerde() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C04', null, new List<String>());
            System.assertEquals(null, p.Aptos_Efetivos__c, 'sem dado fica nulo');
            System.assertEquals(RaizRiskEngine.INSUFICIENTE, p.Estado_Cobertura__c);
            System.assertEquals(RaizRiskEngine.FONTE_SEM_DADO, p.Fonte_Cobertura__c);
            System.assertEquals(false, p.Ponto_Unico_de_Falha__c, 'insuficiente nao e ponto unico');
            // Critico (4) x insuficiente (3) x atualizado (1) = 12 -> Alto, nunca Baixo.
            System.assertEquals(12, p.Risco_Score__c);
            System.assertNotEquals('Baixo', p.Farol__c, 'falta de dado nunca vira verde (regra 4)');
        }
    }

    @IsTest
    static void c05SemHabilitacaoUsaDeclarado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C05', 3, new List<String>());
            System.assertEquals(3, efetivos(p));
            System.assertEquals(RaizRiskEngine.FONTE_DECLARADO, p.Fonte_Cobertura__c);
            System.assertEquals(RaizRiskEngine.COBERTO, p.Estado_Cobertura__c);
        }
    }

    @IsTest
    static void c06HabilitacaoPrevaleceSobreDeclarado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C06', 3, new List<String>{ 'Apto' });
            System.assertEquals(1, efetivos(p), 'evidencia vence declaracao');
            System.assertEquals(RaizRiskEngine.FONTE_HABILITACOES, p.Fonte_Cobertura__c);
            System.assertEquals(true, p.Ponto_Unico_de_Falha__c);
            System.assertEquals(8000, p.Exposicao_Financeira__c, '1000 x 8');
        }
    }

    @IsTest
    static void c07EmTreinamentoNaoContaComoApto() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C07', null, new List<String>{ 'Apto', 'Em treinamento', 'Suspensa' });
            System.assertEquals(3, p.Habilitacoes_Registradas__c);
            System.assertEquals(1, efetivos(p), 'so Apto conta');
            System.assertEquals(RaizRiskEngine.PONTO_UNICO, p.Estado_Cobertura__c);
        }
    }

    @IsTest
    static void c08ValidadePassadaViraVencidaNaGravacao() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C08', null, new List<String>{ 'Apto', 'Apto' });
            Habilitacao__c h = [SELECT Id FROM Habilitacao__c WHERE Processo__c = :p.Id LIMIT 1];
            h.Valida_Ate__c = Date.today().addDays(-1);
            update h;
            System.assertEquals('Vencida', [SELECT Status__c FROM Habilitacao__c WHERE Id = :h.Id].Status__c);
            System.assertEquals(1, efetivos(ler(p.Id)), 'vencida nao conta');
        }
    }

    @IsTest
    static void c09JobDiarioVenceOQueExpirou() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C09', null, new List<String>{ 'Apto', 'Apto' });
            System.assertEquals(2, efetivos(p));
            // Simula o passar do tempo: grava validade passada contornando o gatilho.
            Habilitacao__c h = [SELECT Id FROM Habilitacao__c WHERE Processo__c = :p.Id LIMIT 1];
            RaizHabilitacaoHandler.desligado = true;
            h.Valida_Ate__c = Date.today().addDays(-3);
            h.Status__c = 'Apto';
            update h;
            RaizHabilitacaoHandler.desligado = false;
            System.assertEquals(2, efetivos(ler(p.Id)), 'antes do job o roll-up ainda conta');

            Test.startTest();
            Database.executeBatch(new RaizHabilitacaoVencimentoJob(), 200);
            Test.stopTest();

            System.assertEquals('Vencida', [SELECT Status__c FROM Habilitacao__c WHERE Id = :h.Id].Status__c);
            System.assertEquals(1, efetivos(ler(p.Id)), 'depois do job a contagem cai');
        }
    }

    @IsTest
    static void c09bAgendamentoDoJob() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Test.startTest();
            String jobId = System.schedule('RAIZ teste', '0 0 5 * * ?', new RaizHabilitacaoVencimentoJob());
            Test.stopTest();
            System.assertNotEquals(null, jobId);
        }
    }

    @IsTest
    static void c10ExposicaoSoEmPontoUnico() {
        System.assertEquals(8000, RaizRiskEngine.exposicao(true, 1000, 8));
        System.assertEquals(0, RaizRiskEngine.exposicao(false, 1000, 8));
        System.assertEquals(0, RaizRiskEngine.exposicao(null, 1000, 8));
        System.assertEquals(0, RaizRiskEngine.exposicao(true, null, 8));
    }

    @IsTest
    static void c11ExposicaoIncompletaESinalizada() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('C11');
            Processo_Critico__c p = RaizTestData.processo(a.Id, 'C11', 'Alto', 1, null, 8);
            insert p;
            Processo_Critico__c lido = ler(p.Id);
            System.assertEquals(true, lido.Ponto_Unico_de_Falha__c);
            System.assertEquals(false, lido.Exposicao_Completa__c, 'sem impacto/hora a exposicao esta subestimada');
            System.assertEquals(false, RaizRiskEngine.exposicaoCompleta(true, null, 8));
            System.assertEquals(true, RaizRiskEngine.exposicaoCompleta(false, null, null));
        }
    }

    @IsTest
    static void c12RegistroVencidoDobraOScore() {
        Date hoje = Date.newInstance(2026, 10, 17);
        System.assertEquals(false, RaizRiskEngine.atualizado('Registrado', hoje.addMonths(-10), 6, hoje));
        System.assertEquals(true, RaizRiskEngine.atualizado('Registrado', hoje.addMonths(-2), 6, hoje));
        System.assertEquals(false, RaizRiskEngine.atualizado('Desatualizado', hoje, 6, hoje));
        System.assertEquals(false, RaizRiskEngine.atualizado('Registrado', null, 6, hoje));
        System.assertEquals(true, RaizRiskEngine.atualizado('Registrado', hoje.addMonths(-5), null, hoje), 'padrao 6 meses');
        System.assertEquals(
            2 * RaizRiskEngine.score('Alto', 1, true),
            RaizRiskEngine.score('Alto', 1, false),
            'desatualizado dobra'
        );
    }

    @IsTest
    static void c13MesmaPessoaDuasVezesEBloqueada() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('C13', null, new List<String>{ 'Apto' });
            Habilitacao__c existente = [
                SELECT Profissional__c, Chave_Par__c
                FROM Habilitacao__c
                WHERE Processo__c = :p.Id
                LIMIT 1
            ];
            System.assertEquals(
                RaizHabilitacaoHandler.chavePar(p.Id, existente.Profissional__c),
                existente.Chave_Par__c
            );
            Database.SaveResult sr = Database.insert(
                RaizTestData.habilitacao(p.Id, existente.Profissional__c, 'Apto', null),
                false
            );
            System.assertEquals(false, sr.isSuccess(), 'duplicata inflaria a cobertura');
            System.assertEquals(1, efetivos(ler(p.Id)));
        }
    }

    @IsTest
    static void c14FormulaEMotorConcordam() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('C14');
            List<String> crits = new List<String>{ 'Critico', 'Alto', 'Medio', 'Baixo' };
            List<Integer> declarados = new List<Integer>{ null, 0, 1, 2, 3 };
            List<Date> revisoes = new List<Date>{ Date.today(), Date.today().addMonths(-10), null };
            List<Decimal> impactos = new List<Decimal>{ 250, null };
            List<Processo_Critico__c> ps = new List<Processo_Critico__c>();
            Integer n = 0;
            for (String c : crits) {
                for (Integer d : declarados) {
                    for (Date r : revisoes) {
                        for (Decimal imp : impactos) {
                            Processo_Critico__c p = RaizTestData.processo(a.Id, 'C14-' + (n++), c, d, imp, 6);
                            p.Ultima_Revisao__c = r;
                            ps.add(p);
                        }
                    }
                }
            }
            insert ps; // 120 combinacoes
            Integer conferidos = 0;
            for (Processo_Critico__c p : [
                SELECT
                    Name,
                    Criticidade__c,
                    Impacto_Hora__c,
                    Horas_Para_Restabelecer__c,
                    Atualizado__c,
                    Pessoas_Aptas__c,
                    Habilitacoes_Registradas__c,
                    Aptos_Habilitados__c,
                    Aptos_Efetivos__c,
                    Estado_Cobertura__c,
                    Fonte_Cobertura__c,
                    Ponto_Unico_de_Falha__c,
                    Exposicao_Financeira__c,
                    Exposicao_Completa__c,
                    Risco_Score__c,
                    Farol__c
                FROM Processo_Critico__c
                WHERE Conta__c = :a.Id
            ]) {
                Integer aptos = RaizRiskEngine.aptosEfetivos(
                    p.Habilitacoes_Registradas__c.intValue(),
                    p.Aptos_Habilitados__c.intValue(),
                    p.Pessoas_Aptas__c
                );
                RaizRiskEngine.Avaliacao av = RaizRiskEngine.avaliar(p, aptos);
                String ctx = p.Name + ' ';
                System.assertEquals(efetivos(p), aptos, ctx + 'aptos');
                System.assertEquals(p.Estado_Cobertura__c, av.estado, ctx + 'estado');
                System.assertEquals(
                    p.Fonte_Cobertura__c,
                    RaizRiskEngine.fonte(p.Habilitacoes_Registradas__c.intValue(), p.Pessoas_Aptas__c),
                    ctx + 'fonte'
                );
                System.assertEquals(p.Ponto_Unico_de_Falha__c, av.pontoUnico, ctx + 'ponto unico');
                System.assert(p.Exposicao_Financeira__c == av.exposicao, ctx + 'exposicao ' + p.Exposicao_Financeira__c + ' x ' + av.exposicao);
                System.assertEquals(p.Exposicao_Completa__c, av.exposicaoCompleta, ctx + 'exposicao completa');
                System.assertEquals(p.Risco_Score__c.intValue(), av.score, ctx + 'score');
                System.assertEquals(p.Farol__c, av.farol, ctx + 'farol');
                conferidos++;
            }
            System.assertEquals(120, conferidos);
        }
    }

    @IsTest
    static void profissionalDesativadoSuspendeHabilitacoes() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = montar('DES', null, new List<String>{ 'Apto', 'Apto' });
            Habilitacao__c h = [SELECT Profissional__c FROM Habilitacao__c WHERE Processo__c = :p.Id LIMIT 1];
            update new Profissional__c(Id = h.Profissional__c, Ativo__c = false);
            System.assertEquals(1, efetivos(ler(p.Id)), 'quem saiu nao cobre');
            // Nova habilitacao Apto para inativo ja nasce Suspensa.
            Id contaId = [SELECT Conta__c FROM Processo_Critico__c WHERE Id = :p.Id].Conta__c;
            Processo_Critico__c outro = RaizTestData.processo(contaId, 'DES-2', 'Alto', null, 10, 1);
            insert outro;
            Habilitacao__c nova = RaizTestData.habilitacao(outro.Id, h.Profissional__c, 'Apto', null);
            insert nova;
            System.assertEquals('Suspensa', [SELECT Status__c FROM Habilitacao__c WHERE Id = :nova.Id].Status__c);
        }
    }

    @IsTest
    static void unidadesDoMotor() {
        System.assertEquals(null, RaizRiskEngine.aptosEfetivos(0, 0, null));
        System.assertEquals(0, RaizRiskEngine.aptosEfetivos(2, null, 5));
        System.assertEquals(RaizRiskEngine.SEM_COBERTURA, RaizRiskEngine.estado(-1));
        System.assertEquals(4, RaizRiskEngine.pesoCriticidade('Critico'));
        System.assertEquals(1, RaizRiskEngine.pesoCriticidade(null));
        System.assertEquals(3, RaizRiskEngine.fatorDependencia(null));
        System.assertEquals(2, RaizRiskEngine.fatorDependencia(2));
        System.assertEquals(1, RaizRiskEngine.fatorDependencia(5));
        System.assertEquals('Baixo', RaizRiskEngine.farol(null));
        System.assertEquals('Critico', RaizRiskEngine.farol(16));
        System.assertEquals('Alto', RaizRiskEngine.farol(9));
        System.assertEquals('Medio', RaizRiskEngine.farol(5));
        System.assertEquals('Baixo', RaizRiskEngine.farol(4));
        Date hoje = Date.today();
        System.assertEquals(true, RaizRiskEngine.vigente('Apto', true, null, hoje));
        System.assertEquals(false, RaizRiskEngine.vigente('Apto', false, null, hoje));
        System.assertEquals(false, RaizRiskEngine.vigente('Apto', true, hoje.addDays(-1), hoje));
        System.assertEquals(false, RaizRiskEngine.vigente('Em treinamento', true, null, hoje));
    }
}
