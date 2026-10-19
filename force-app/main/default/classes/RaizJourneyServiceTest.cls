/**
 * RaizJourneyServiceTest — cadastro guiado (Onda 6): caminho feliz e estados de erro.
 */
@IsTest
private class RaizJourneyServiceTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
        RaizTestData.criarAprovador();
        insert new Project__c(Name = RaizKnowledgeService.PROJETO_RAIZ);
    }

    private static Processo_Critico__c processo(String nome) {
        Processo_Critico__c p = RaizTestData.processo(RaizTestData.conta('JOR ' + nome).Id, nome, 'Critico', 1, 100, 2);
        insert p;
        return p;
    }

    private static RaizJourneyService.Dados completo(Id processoId, Id revisorId) {
        RaizJourneyService.Dados x = new RaizJourneyService.Dados();
        x.processoId = processoId;
        x.titulo = 'Emissão de nota de devolução';
        x.tipo = 'Procedimento operacional';
        x.categoria = 'Fiscal';
        x.resumo = '<p>Como emitir a nota de devolução sem depender de uma pessoa.</p>';
        x.palavrasChave = 'nota, devolução';
        x.revisorId = revisorId;
        x.dataReferencia = Date.today();
        x.proximaRevisao = Date.today().addMonths(6);
        x.prazoRevisao = Date.today().addDays(5);
        x.criticidade = 'Critica';
        x.preRequisitos = '<p>Acesso ao sistema fiscal.</p>';
        x.etapas = '<ol><li>Abrir o pedido</li><li>Emitir</li></ol>';
        x.resultadoEsperado = '<p>Nota autorizada.</p>';
        x.excecoes = '<p>Rejeição: corrigir o CFOP.</p>';
        x.contingencia = '<p>Emitir em contingência.</p>';
        x.referencias = '<p>Manual interno (fictício).</p>';
        return x;
    }

    private static Set<Integer> etapas(RaizJourneyService.Revisao rv) {
        Set<Integer> s = new Set<Integer>();
        for (RaizJourneyService.Item i : rv.bloqueios) s.add(i.etapa);
        return s;
    }

    @IsTest
    static void contextoTrazProcessosOpcoesERevisores() {
        User revisor = RaizTestData.usuarioAprovador();
        System.runAs(RaizTestData.usuarioRaiz()) {
            processo('Ctx');
            RaizJourneyService.Contexto c = RaizJourneyService.getContexto();
            System.assertEquals(1, c.processos.size());
            System.assertEquals('Sem documento', c.processos[0].situacaoDocumento);
            System.assertEquals('Critica', c.processos[0].criticidadeDocumento);
            System.assertEquals(4, c.tipos.size());
            System.assert(!c.categorias.isEmpty());
            Set<Id> revs = new Set<Id>();
            for (RaizGovernancaService.Revisor r : c.revisores) revs.add(r.id);
            System.assert(revs.contains(revisor.Id));
            System.assert(!revs.contains(UserInfo.getUserId()));
        }
    }

    @IsTest
    static void caminhoFelizGravaEncaminhaEExplicaProximosPassos() {
        User autor = RaizTestData.usuarioRaiz();
        User revisor = RaizTestData.usuarioAprovador();
        System.runAs(autor) {
            Processo_Critico__c p = processo('Feliz');
            String payload = JSON.serialize(completo(p.Id, revisor.Id));
            RaizJourneyService.Revisao rv = RaizJourneyService.validar(payload, true);
            System.assert(rv.bloqueios.isEmpty(), String.valueOf(rv.bloqueios));
            System.assert(rv.avisos.isEmpty(), String.valueOf(rv.avisos));

            RaizJourneyService.Resultado r = RaizJourneyService.salvar(payload, true);
            System.assertEquals(true, r.criado);
            System.assertEquals(true, r.encaminhado);
            System.assertEquals('Em Analise', r.status);
            System.assertNotEquals(null, r.cartao);
            System.assert(r.proximosPassos.size() >= 3);

            Business_Rule__c d = [
                SELECT Status__c, Tipo_Documento__c, Revisor__c, Prazo_Revisao__c, Proxima_Revisao__c, Business_Owner__c,
                    Pre_Requisitos__c, Descricao_Demanda__c, Criterios_Aceite__c, Cenarios_Teste__c, Plano_Contingencia__c,
                    Referencias__c, Domain__c, Criticality__c, Keywords__c, Project__c
                FROM Business_Rule__c
                WHERE Id = :r.documentoId
            ];
            System.assertEquals('Em Analise', d.Status__c);
            System.assertEquals('Procedimento operacional', d.Tipo_Documento__c);
            System.assertEquals(revisor.Id, d.Revisor__c);
            System.assertEquals(autor.Id, d.Business_Owner__c);
            System.assertEquals(Date.today().addDays(5), d.Prazo_Revisao__c);
            System.assert(d.Descricao_Demanda__c.contains('Emitir'));
            System.assert(d.Plano_Contingencia__c.contains('contingência'));
            System.assertEquals('Fiscal', d.Domain__c);
            System.assertEquals('Critica', d.Criticality__c);
            System.assertNotEquals(null, d.Project__c);
            System.assertNotEquals('Sem documento', RaizJourneyService.getContexto().processos[0].situacaoDocumento);
        }
    }

    @IsTest
    static void rascunhoERetomadoSemDuplicar() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = processo('Retomar');
            RaizJourneyService.Dados x = completo(p.Id, null);
            x.etapas = null;
            RaizJourneyService.Resultado r1 = RaizJourneyService.salvar(JSON.serialize(x), false);
            System.assertEquals(true, r1.criado);
            System.assertEquals('Draft', r1.status);
            System.assertEquals(false, r1.encaminhado);

            RaizJourneyService.Situacao s = RaizJourneyService.getSituacao(p.Id);
            System.assertEquals('RASCUNHO', s.estado);
            System.assertEquals(true, s.podeContinuar);
            System.assertEquals(r1.documentoId, s.dados.documentoId);
            System.assertEquals('Emissão de nota de devolução', s.dados.titulo);

            s.dados.etapas = '<p>Agora com etapas</p>';
            RaizJourneyService.Resultado r2 = RaizJourneyService.salvar(JSON.serialize(s.dados), false);
            System.assertEquals(false, r2.criado, 'atualiza, nao cria');
            System.assertEquals(r1.documentoId, r2.documentoId);
            System.assertEquals(1, [SELECT COUNT() FROM Business_Rule__c WHERE Processo_Critico__c = :p.Id]);
            // Sem documentoId (ex.: sessao interrompida e reaberta): tambem nao duplica.
            x.documentoId = null;
            RaizJourneyService.salvar(JSON.serialize(x), false);
            System.assertEquals(1, [SELECT COUNT() FROM Business_Rule__c WHERE Processo_Critico__c = :p.Id]);
        }
    }

    @IsTest
    static void bloqueiosApontamATela() {
        User autor = RaizTestData.usuarioRaiz();
        System.runAs(autor) {
            RaizJourneyService.Dados vazio = new RaizJourneyService.Dados();
            Set<Integer> e = etapas(RaizJourneyService.validar(JSON.serialize(vazio), false));
            System.assert(e.contains(2) && e.contains(3) && e.contains(4), String.valueOf(e));

            Processo_Critico__c p = processo('Bloq');
            RaizJourneyService.Dados x = completo(p.Id, autor.Id);
            x.dataReferencia = Date.today().addDays(1);
            x.proximaRevisao = Date.today();
            x.prazoRevisao = Date.today().addDays(-1);
            RaizJourneyService.Revisao rv = RaizJourneyService.validar(JSON.serialize(x), true);
            String todas = '';
            for (RaizJourneyService.Item i : rv.bloqueios) {
                System.assertEquals(4, i.etapa, i.mensagem);
                todas += i.mensagem + ' | ';
            }
            System.assert(todas.contains('próprio documento'), todas);
            System.assert(todas.contains('futuro'), todas);
            System.assert(todas.contains('data futura'), todas);
            System.assert(todas.contains('já passou'), todas);

            x = completo(p.Id, null);
            x.tipo = 'Inexistente';
            x.titulo = ' ';
            Set<Integer> e3 = etapas(RaizJourneyService.validar(JSON.serialize(x), false));
            System.assertEquals(new Set<Integer>{ 3 }, e3);
            try {
                RaizJourneyService.salvar(JSON.serialize(x), false);
                System.assert(false, 'deveria barrar');
            } catch (AuraHandledException ex) {
                System.assert(ex.getMessage().startsWith('Corrija antes de salvar'), ex.getMessage());
            }
            System.assertEquals(0, [SELECT COUNT() FROM Business_Rule__c WHERE Processo_Critico__c = :p.Id]);
        }
    }

    @IsTest
    static void revisorSemPermissaoEBarrado() {
        User sem = RaizTestData.usuarioSemAcesso();
        if (sem == null) return;
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = processo('SemPerm');
            RaizJourneyService.Revisao rv = RaizJourneyService.validar(JSON.serialize(completo(p.Id, sem.Id)), true);
            System.assertEquals(1, rv.bloqueios.size());
            System.assert(rv.bloqueios[0].mensagem.contains('permissão de aprovação'));
        }
    }

    @IsTest
    static void documentoEmRevisaoOuPublicadoNaoEDuplicado() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Id proj = [SELECT Id FROM Project__c LIMIT 1].Id;
            Processo_Critico__c emRev = processo('EmRev');
            Processo_Critico__c pub = processo('Pub');
            insert new List<Business_Rule__c>{
                new Business_Rule__c(Title__c = 'A', Status__c = 'Em Analise', Criticality__c = 'Alta', Domain__c = 'Fiscal', Processo_Critico__c = emRev.Id, Project__c = proj),
                new Business_Rule__c(Title__c = 'B', Status__c = 'Publicada', Criticality__c = 'Alta', Domain__c = 'Fiscal', Processo_Critico__c = pub.Id, Project__c = proj,
                    Proposito_Documento__c = '<p>P</p>', Descricao_Demanda__c = '<p>D</p>', Criterios_Aceite__c = '<p>C</p>', Cenarios_Teste__c = '<p>T</p>')
            };
            RaizJourneyService.Situacao s1 = RaizJourneyService.getSituacao(emRev.Id);
            System.assertEquals('EM_REVISAO', s1.estado);
            System.assertEquals(false, s1.podeContinuar);
            RaizJourneyService.Situacao s2 = RaizJourneyService.getSituacao(pub.Id);
            System.assertEquals('PUBLICADO', s2.estado);
            System.assert(s2.mensagem.contains('já está publicado'));
            try {
                RaizJourneyService.salvar(JSON.serialize(completo(pub.Id, null)), false);
                System.assert(false, 'publicado nao recebe segundo documento');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Knowledge Hub'), e.getMessage());
            }
            System.assertEquals(1, [SELECT COUNT() FROM Business_Rule__c WHERE Processo_Critico__c = :pub.Id]);

            // Rascunho de OUTRO processo informado: recusado.
            RaizJourneyService.Dados x = completo(emRev.Id, null);
            Processo_Critico__c outro = processo('Outro');
            x.processoId = outro.Id;
            x.documentoId = [SELECT Id FROM Business_Rule__c WHERE Processo_Critico__c = :pub.Id].Id;
            System.assert(etapas(RaizJourneyService.validar(JSON.serialize(x), false)).contains(2));
        }
    }

    @IsTest
    static void encaminharIncompletoAvisaMasNaoBloqueia() {
        // Decisao D6: o Hub nao exige conteudo para ir a revisao; o cadastro avisa.
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = processo('Incompleto');
            RaizJourneyService.Dados x = completo(p.Id, null);
            x.etapas = null;
            x.prazoRevisao = null;
            x.resultadoEsperado = null;
            RaizJourneyService.Resultado r = RaizJourneyService.salvar(JSON.serialize(x), true);
            System.assertEquals(true, r.encaminhado);
            String avisos = String.join(r.avisos, ' | ');
            System.assert(avisos.contains('Recomendado antes de encaminhar'), avisos);
            System.assert(avisos.contains('Etapas operacionais'), avisos);
            System.assert(avisos.contains('Revisor'), avisos);
            System.assert(avisos.contains('Sem prazo'), avisos);
            System.assert(avisos.contains('Necessário para aprovar'), avisos);
        }
    }

    @IsTest
    static void semProjetoDaBaseExplicaOQueFazer() {
        delete [SELECT Id FROM Project__c];
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = processo('SemProj');
            try {
                RaizJourneyService.salvar(JSON.serialize(completo(p.Id, null)), false);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Rode a carga'), e.getMessage());
            }
        }
    }

    @IsTest
    static void entradasInvalidas() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            for (String entrada : new List<String>{ null, '{', '' }) {
                try {
                    RaizJourneyService.validar(entrada, false);
                    System.assert(false);
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().length() > 5);
                }
            }
            try {
                RaizJourneyService.getSituacao(null);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Escolha'));
            }
            Processo_Critico__c p = processo('Apagado');
            Id idApagado = p.Id;
            delete p;
            try {
                RaizJourneyService.getSituacao(idApagado);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('não encontrado'), e.getMessage());
            }
        }
    }

    @IsTest
    static void usuarioSemPermissaoRecebeMensagem() {
        User sem = RaizTestData.usuarioSemAcesso();
        if (sem == null) return;
        System.runAs(sem) {
            Boolean falhou = false;
            try {
                RaizJourneyService.getContexto();
            } catch (AuraHandledException e) {
                falhou = true;
                System.assert(e.getMessage().length() > 0);
            }
            System.assert(falhou || Schema.SObjectType.Processo_Critico__c.isAccessible());
        }
    }
}
