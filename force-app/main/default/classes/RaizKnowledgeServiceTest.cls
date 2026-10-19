/**
 * RaizKnowledgeServiceTest — Knowledge Hub (Onda 5).
 */
@IsTest
private class RaizKnowledgeServiceTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
        RaizTestData.criarAprovador();
        insert new Project__c(Name = RaizKnowledgeService.PROJETO_RAIZ);
    }

    private static Id projetoId() {
        return [SELECT Id FROM Project__c WHERE Name = :RaizKnowledgeService.PROJETO_RAIZ LIMIT 1].Id;
    }

    private static Business_Rule__c doc(Id processoId, String status, Boolean completo) {
        Business_Rule__c d = new Business_Rule__c(
            Title__c = 'Doc teste',
            Status__c = status,
            Criticality__c = 'Alta',
            Domain__c = 'Fiscal',
            Processo_Critico__c = processoId,
            Project__c = projetoId()
        );
        if (completo) {
            d.Proposito_Documento__c = '<p>Proposito</p>';
            d.Descricao_Demanda__c = '<p>Descricao</p>';
            d.Criterios_Aceite__c = '<p>Criterios</p>';
            d.Cenarios_Teste__c = '<p>Cenarios</p>';
        }
        return d;
    }

    private static List<Processo_Critico__c> processos(Id contaId, Integer n) {
        List<Processo_Critico__c> ps = new List<Processo_Critico__c>();
        for (Integer i = 0; i < n; i++) {
            Processo_Critico__c p = RaizTestData.processo(contaId, 'Proc ' + i, 'Critico', 1, 100, 2);
            p.Status_Registro__c = 'Sem registro';
            p.Ultima_Revisao__c = null;
            ps.add(p);
        }
        insert ps;
        return ps;
    }

    private static RaizKnowledgeService.Coluna coluna(RaizKnowledgeService.Quadro q, String chave) {
        for (RaizKnowledgeService.Coluna c : q.colunas) {
            if (c.chave == chave) return c;
        }
        return null;
    }

    @IsTest
    static void quadroTemCincoColunasEBacklog() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('KH');
            List<Processo_Critico__c> ps = processos(a.Id, 3);
            insert new List<Business_Rule__c>{ doc(ps[1].Id, 'Draft', false), doc(ps[2].Id, 'Publicada', true) };
            // Documento sem processo nao entra no quadro.
            insert doc(null, 'Draft', false);

            RaizKnowledgeService.Quadro q = RaizKnowledgeService.getQuadro(a.Id);
            System.assertEquals(5, q.colunas.size());
            System.assertEquals('Backlog', q.colunas[0].rotulo);
            System.assertEquals('Em elaboração', q.colunas[1].rotulo);
            System.assertEquals('Publicado', q.colunas[4].rotulo);
            System.assertEquals(1, coluna(q, 'Backlog').total);
            System.assertEquals(1, coluna(q, 'Draft').total);
            System.assertEquals(1, coluna(q, 'Publicada').total);
            System.assertEquals(2, q.documentos);
            System.assertEquals(1, q.publicados);
            System.assertEquals(1, q.processosSemDocumento);
            System.assertEquals(false, q.podeAprovar);
            RaizKnowledgeService.Cartao rascunho = coluna(q, 'Draft').cartoes[0];
            System.assertEquals(4, rascunho.pendencias.size());
            System.assertEquals(true, rascunho.podeAvancar, 'Draft -> Em revisao nao exige aprovador');
            System.assertEquals('Crítico', rascunho.criticidade);
            System.assertEquals(3, q.premissas.size());
            System.assertEquals(2, RaizKnowledgeService.getQuadro(null).documentos, 'sem filtro de conta; o documento sem processo fica fora');
        }
    }

    @IsTest
    static void criarDocumentoNoBacklog() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('KH2');
            Processo_Critico__c p = processos(a.Id, 1)[0];
            Id docId = RaizKnowledgeService.criarDocumento(p.Id);
            Business_Rule__c d = [
                SELECT Status__c, Criticality__c, Domain__c, Processo_Critico__c, Title__c
                FROM Business_Rule__c
                WHERE Id = :docId
            ];
            System.assertEquals('Draft', d.Status__c);
            System.assertEquals('Critica', d.Criticality__c);
            System.assertEquals('Fiscal', d.Domain__c);
            System.assertEquals(p.Id, d.Processo_Critico__c);
            System.assert(d.Title__c.startsWith('Registro — '));
            for (Id alvo : new List<Id>{ p.Id, null }) {
                try {
                    RaizKnowledgeService.criarDocumento(alvo);
                    System.assert(false, 'deveria recusar');
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().length() > 5);
                }
            }
        }
    }

    @IsTest
    static void semProjetoRaizExplicaOQueFazer() {
        delete [SELECT Id FROM Project__c];
        System.runAs(RaizTestData.usuarioRaiz()) {
            Processo_Critico__c p = processos(RaizTestData.conta('KH3').Id, 1)[0];
            try {
                RaizKnowledgeService.criarDocumento(p.Id);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Rode a carga'), e.getMessage());
            }
        }
    }

    @IsTest
    static void autorNaoAprova() {
        System.runAs(RaizTestData.usuarioRaiz()) {
            Account a = RaizTestData.conta('KH4');
            Processo_Critico__c p = processos(a.Id, 1)[0];
            Business_Rule__c d = doc(p.Id, 'Draft', true);
            insert d;
            RaizKnowledgeService.moverDocumento(d.Id, 1);
            System.assertEquals('Em Analise', [SELECT Status__c FROM Business_Rule__c WHERE Id = :d.Id].Status__c);
            RaizKnowledgeService.Cartao k = coluna(RaizKnowledgeService.getQuadro(a.Id), 'Em Analise').cartoes[0];
            System.assertEquals(false, k.podeAvancar);
            System.assertEquals('Exige permissão de aprovação.', k.motivoBloqueio);
            try {
                RaizKnowledgeService.moverDocumento(d.Id, 1);
                System.assert(false, 'autor nao pode aprovar');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Aprovar documentos'), e.getMessage());
            }
            RaizKnowledgeService.moverDocumento(d.Id, -1);
            System.assertEquals('Draft', [SELECT Status__c FROM Business_Rule__c WHERE Id = :d.Id].Status__c);
        }
    }

    @IsTest
    static void aprovadorPublicaEAtualizaOProcesso() {
        System.runAs(RaizTestData.usuarioAprovador()) {
            Account a = RaizTestData.conta('KH5');
            Processo_Critico__c p = processos(a.Id, 1)[0];
            System.assertEquals(false, [SELECT Atualizado__c FROM Processo_Critico__c WHERE Id = :p.Id].Atualizado__c);
            Business_Rule__c d = doc(p.Id, 'Em Analise', true);
            insert d;
            RaizKnowledgeService.Quadro q = RaizKnowledgeService.getQuadro(a.Id);
            System.assertEquals(true, q.podeAprovar);
            System.assertEquals(true, coluna(q, 'Em Analise').cartoes[0].podeAvancar);

            RaizKnowledgeService.moverDocumento(d.Id, 1);
            RaizKnowledgeService.moverDocumento(d.Id, 1);
            Business_Rule__c pub = [SELECT Status__c, Last_Review_Date__c FROM Business_Rule__c WHERE Id = :d.Id];
            System.assertEquals('Publicada', pub.Status__c);
            System.assertEquals(Date.today(), pub.Last_Review_Date__c);
            Processo_Critico__c depois = [
                SELECT Status_Registro__c, Ultima_Revisao__c, Atualizado__c
                FROM Processo_Critico__c
                WHERE Id = :p.Id
            ];
            System.assertEquals('Registrado', depois.Status_Registro__c);
            System.assertEquals(Date.today(), depois.Ultima_Revisao__c);
            System.assertEquals(true, depois.Atualizado__c, 'publicar torna o registro atualizado');

            try {
                RaizKnowledgeService.moverDocumento(d.Id, 1);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Publicada'), e.getMessage());
            }
            try {
                RaizKnowledgeService.moverDocumento(d.Id, -1);
                System.assert(false, 'publicado nao volta');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().length() > 5);
            }
        }
    }

    @IsTest
    static void conteudoIncompletoBarraAprovacao() {
        System.runAs(RaizTestData.usuarioAprovador()) {
            Account a = RaizTestData.conta('KH6');
            Processo_Critico__c p = processos(a.Id, 1)[0];
            Business_Rule__c d = doc(p.Id, 'Em Analise', false);
            d.Proposito_Documento__c = '<p><br></p>';
            insert d;
            RaizKnowledgeService.Cartao k = coluna(RaizKnowledgeService.getQuadro(a.Id), 'Em Analise').cartoes[0];
            System.assertEquals(false, k.podeAvancar);
            System.assert(k.motivoBloqueio.startsWith('Falta: Propósito'), k.motivoBloqueio);
            try {
                RaizKnowledgeService.moverDocumento(d.Id, 1);
                System.assert(false, 'regra de validacao deveria barrar');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().containsIgnoreCase('preencha'), e.getMessage());
            }
            try {
                RaizKnowledgeService.moverDocumento(null, 1);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('inválido'));
            }
        }
    }

    @IsTest
    static void usuarioSemPermissao() {
        User sem = RaizTestData.usuarioSemAcesso();
        if (sem == null) return;
        System.runAs(sem) {
            Boolean falhou = false;
            try {
                RaizKnowledgeService.getQuadro(null);
            } catch (AuraHandledException e) {
                falhou = true;
                System.assert(e.getMessage().length() > 0);
            }
            System.assert(falhou || Schema.SObjectType.Processo_Critico__c.isAccessible());
        }
    }
}
