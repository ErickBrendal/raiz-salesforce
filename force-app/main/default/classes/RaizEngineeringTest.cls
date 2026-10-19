/**
 * RaizEngineeringTest — verificador e painel do Engineering Status (Onda 8).
 * Prova as regras de ADR-015: preencher nao valida; so o verificador marca Verificado.
 */
@IsTest
private class RaizEngineeringTest {
    @TestSetup
    static void semear() {
        RaizTestData.criarUsuarios();
        RAIZ_Engineering_Status__c ok = funcionalidade('FUNC:OK', 'Implementado');
        RAIZ_Engineering_Status__c ruim = funcionalidade('FUNC:RUIM', 'Implementado');
        RAIZ_Engineering_Status__c plan = funcionalidade('FUNC:PLAN', 'Planejado');
        RAIZ_Engineering_Status__c vazia = funcionalidade('FUNC:VAZIA', 'Implementado');
        insert new List<RAIZ_Engineering_Status__c>{ ok, ruim, plan, vazia };
        insert new List<RAIZ_Engineering_Status__c>{
            componente('Processo_Critico__c', 'Objeto', ok.Id),
            componente('Business_Rule__c.Revisor__c', 'Campo', ok.Id),
            componente('RaizRiskEngine', 'Classe Apex', ok.Id),
            componente('EBL_RAIZ_Cockpit', 'Permission Set', ok.Id),
            componente('ClasseQueNaoExisteRaiz', 'Classe Apex', ruim.Id),
            componente('Business_Rule__c.CampoInexistente__c', 'Campo', ruim.Id),
            componente('raizKnowledgeHub', 'LWC', ruim.Id),
            componente('Futuro_Planejado__c', 'Objeto', plan.Id)
        };
        // o componente planejado
        RAIZ_Engineering_Status__c fp = [SELECT Id FROM RAIZ_Engineering_Status__c WHERE API_Name__c = 'Futuro_Planejado__c'];
        fp.Status_Implementacao__c = 'Planejado';
        update fp;
    }

    private static RAIZ_Engineering_Status__c funcionalidade(String api, String status) {
        return new RAIZ_Engineering_Status__c(
            Name = api,
            API_Name__c = api,
            Nivel__c = 'Funcionalidade',
            Tipo_Componente__c = 'Funcionalidade',
            Modulo__c = 'Plataforma',
            Status_Implementacao__c = status,
            Estado_Validacao__c = 'Verificado' // declarado errado de proposito: o verificador corrige
        );
    }

    private static RAIZ_Engineering_Status__c componente(String api, String tipo, Id funcId) {
        return new RAIZ_Engineering_Status__c(
            Name = api,
            API_Name__c = api,
            Nivel__c = 'Componente',
            Tipo_Componente__c = tipo,
            Modulo__c = 'Plataforma',
            Status_Implementacao__c = 'Implementado',
            Funcionalidade__c = funcId
        );
    }

    private static Map<String, RAIZ_Engineering_Status__c> porApi() {
        Map<String, RAIZ_Engineering_Status__c> m = new Map<String, RAIZ_Engineering_Status__c>();
        for (RAIZ_Engineering_Status__c s : [
            SELECT API_Name__c, Estado_Validacao__c, Resultado_Verificacao__c, Ultima_Verificacao__c
            FROM RAIZ_Engineering_Status__c
        ]) {
            m.put(s.API_Name__c, s);
        }
        return m;
    }

    @IsTest
    static void verificadorConfereNaOrgEPrevaleceSobreODeclarado() {
        Test.startTest();
        RaizEngineeringVerifier.Resultado r = RaizEngineeringVerifier.verificar();
        Test.stopTest();
        Map<String, RAIZ_Engineering_Status__c> m = porApi();
        System.assertEquals('Verificado', m.get('Processo_Critico__c').Estado_Validacao__c);
        System.assertEquals('Verificado', m.get('Business_Rule__c.Revisor__c').Estado_Validacao__c);
        System.assertEquals('Verificado', m.get('RaizRiskEngine').Estado_Validacao__c);
        System.assertEquals('Verificado', m.get('EBL_RAIZ_Cockpit').Estado_Validacao__c);
        System.assertEquals('Falhou', m.get('ClasseQueNaoExisteRaiz').Estado_Validacao__c);
        System.assertEquals('Falhou', m.get('Business_Rule__c.CampoInexistente__c').Estado_Validacao__c);
        System.assertEquals('Nao verificavel', m.get('raizKnowledgeHub').Estado_Validacao__c, 'Apex não enxerga LWC');
        System.assertEquals('Declarado', m.get('Futuro_Planejado__c').Estado_Validacao__c);

        System.assertEquals('Verificado', m.get('FUNC:OK').Estado_Validacao__c);
        System.assert(m.get('FUNC:OK').Resultado_Verificacao__c.startsWith('4 de 4'));
        System.assertEquals('Falhou', m.get('FUNC:RUIM').Estado_Validacao__c);
        System.assertEquals('Declarado', m.get('FUNC:PLAN').Estado_Validacao__c, 'o "Verificado" declarado foi corrigido');
        System.assertEquals('Nao verificavel', m.get('FUNC:VAZIA').Estado_Validacao__c);
        System.assertNotEquals(null, m.get('FUNC:OK').Ultima_Verificacao__c);

        System.assertEquals(12, r.total);
        System.assertEquals(3, r.falhas, '2 componentes + 1 funcionalidade');
        System.assertEquals(5, r.verificados);
        System.assertEquals(2, r.naoVerificaveis);
        System.assertEquals(2, r.planejados);
        System.assertEquals(1, [SELECT COUNT() FROM RAIZ_Log_Execucao__c WHERE Tipo__c = 'Verificacao']);
        System.assert([SELECT COUNT() FROM RAIZ_Evidencia__c WHERE Resultado__c = 'Reprovado'] >= 2);
    }

    @IsTest
    static void reverificarNaoDuplicaEvidencias() {
        RaizEngineeringVerifier.executar();
        Integer antes = [SELECT COUNT() FROM RAIZ_Evidencia__c];
        RaizEngineeringVerifier.executar();
        System.assertEquals(antes, [SELECT COUNT() FROM RAIZ_Evidencia__c], 'mesma chave atualiza a mesma evidência');
    }

    @IsTest
    static void lwcComEvidenciaDoCliRecenteFicaVerificado() {
        RAIZ_Engineering_Status__c lwc = [SELECT Id FROM RAIZ_Engineering_Status__c WHERE API_Name__c = 'raizKnowledgeHub'];
        insert new RAIZ_Evidencia__c(
            Item__c = lwc.Id,
            Tipo__c = 'Metadado na org',
            Origem__c = 'sf CLI',
            Resultado__c = 'Aprovado',
            Verificado_Em__c = DateTime.now(),
            Chave__c = 'raizKnowledgeHub|Metadado na org|sf CLI'
        );
        RaizEngineeringVerifier.executar();
        System.assertEquals('Verificado', porApi().get('raizKnowledgeHub').Estado_Validacao__c);
    }

    @IsTest
    static void painelMostraRegrasESeparaFuncionalidadeDeComponente() {
        insert new RAIZ_Implantacao__c(
            Deploy_Id__c = '0AfTESTE000000001',
            Onda__c = 'Onda 7',
            Executado_Em__c = DateTime.now(),
            Testes_Executados__c = 77,
            Testes_Aprovados__c = 77,
            Componentes__c = 42,
            Resultado__c = 'Sucesso',
            Origem__c = 'sf CLI'
        );
        RaizLog.registrar('Automacao', 'submissao', 'Bloqueado', null, 'T1', 'teste');
        RaizEngineeringVerifier.executar();
        RaizEngineeringService.Painel p;
        System.runAs(RaizTestData.usuarioRaiz()) {
            p = RaizEngineeringService.getPainel();
        }
        System.assertEquals(null, p.erro, 'painel sem erro: ' + String.valueOf(p.erro));
        System.assertEquals(4, p.funcionalidades.size());
        System.assertEquals(8, p.componentes.size());
        System.assertEquals(9, p.indicadores.size());
        Map<String, RaizEngineeringService.Indicador> ind = new Map<String, RaizEngineeringService.Indicador>();
        for (RaizEngineeringService.Indicador i : p.indicadores) {
            System.assert(String.isNotBlank(i.regra), 'todo indicador tem regra: ' + i.chave);
            ind.put(i.chave, i);
        }
        System.assertEquals('3 de 4', ind.get('func-impl').valor);
        System.assertEquals('1 de 3', ind.get('func-val').valor);
        System.assertEquals('4 de 8', ind.get('comp-ver').valor);
        System.assertEquals('2', ind.get('comp-falha').valor);
        System.assertEquals('77 de 77', ind.get('testes').valor);
        System.assert(ind.get('automacao').valor.contains('1 bloqueadas'), ind.get('automacao').valor);
        System.assertNotEquals(null, p.ultimaVerificacao);
        System.assertEquals(1, p.implantacoes.size());
        System.assert(!p.pendencias.isEmpty());
        for (RaizEngineeringService.Item f : p.funcionalidades) {
            if (f.api == 'FUNC:OK') {
                System.assertEquals(4, f.componentes);
                System.assertEquals(4, f.componentesVerificados);
            }
        }
    }

    @IsTest
    static void semPermissaoDevolveMensagem() {
        User sem = RaizTestData.usuarioSemAcesso();
        if (sem == null) return;
        RaizEngineeringService.Painel p;
        System.runAs(sem) {
            p = RaizEngineeringService.getPainel();
        }
        System.assert(p.erro != null || Schema.SObjectType.RAIZ_Engineering_Status__c.isAccessible());
    }

    @IsTest
    static void tiposSemExemploSaoConferidos() {
        Id f = [SELECT Id FROM RAIZ_Engineering_Status__c WHERE API_Name__c = 'FUNC:VAZIA'].Id;
        Map<String, String> m = new Map<String, String>{
            'TrgNaoExisteRaiz' => 'Trigger',
            'FlowNaoExisteRaiz' => 'Flow',
            'JobNaoExisteRaiz' => 'Job agendado',
            'AbaNaoExisteRaiz' => 'Aba',
            'AppNaoExisteRaiz' => 'App',
            'NotifNaoExisteRaiz' => 'Notificacao',
            'NcNaoExisteRaiz' => 'Named Credential',
            'TipoLivreRaiz' => 'Funcionalidade'
        };
        List<RAIZ_Engineering_Status__c> cs = new List<RAIZ_Engineering_Status__c>();
        for (String api : m.keySet()) cs.add(componente(api, m.get(api), f));
        cs[0].Teste_Associado__c = 'RaizEngineeringTest';
        insert cs;
        RaizEngineeringVerifier.Resultado r = RaizEngineeringVerifier.executar();
        System.assertEquals(20, r.total);
        Map<String, RAIZ_Engineering_Status__c> e = porApi();
        System.assertEquals('Falhou', e.get('FUNC:VAZIA').Estado_Validacao__c);
        System.assertEquals('Nao verificavel', e.get('TipoLivreRaiz').Estado_Validacao__c);
        System.assertEquals('Falhou', e.get('FlowNaoExisteRaiz').Estado_Validacao__c);
    }
}
