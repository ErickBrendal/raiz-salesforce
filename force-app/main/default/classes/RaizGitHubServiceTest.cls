/**
 * RaizGitHubServiceTest — Integration Hub (Onda 9) com HttpCalloutMock.
 * Cobre 200, 401, 403 (limite e acesso), 404, 429, 5xx, timeout, JSON invalido,
 * repositorio sem release, integracao desativada, idempotencia e ausencia de segredo no log.
 */
@IsTest
private class RaizGitHubServiceTest {
    private class Mock implements HttpCalloutMock {
        Integer repoStatus;
        Integer relStatus;
        String relBody;
        Map<String, String> cabecalhos = new Map<String, String>();
        Boolean timeout = false;
        Integer chamadas = 0;
        Mock(Integer repoStatus, Integer relStatus, String relBody) {
            this.repoStatus = repoStatus;
            this.relStatus = relStatus;
            this.relBody = relBody;
        }
        public HttpResponse respond(HttpRequest req) {
            chamadas++;
            if (timeout) throw new CalloutException('Read timed out');
            System.assertEquals('GET', req.getMethod(), 'somente leitura');
            System.assert(req.getEndpoint().startsWith('callout:RAIZ_GitHub/repos/demo-owner/demo-repo'), req.getEndpoint());
            System.assertEquals('2022-11-28', req.getHeader('X-GitHub-Api-Version'));
            HttpResponse r = new HttpResponse();
            Boolean releases = req.getEndpoint().contains('/releases');
            r.setStatusCode(releases ? relStatus : repoStatus);
            r.setBody(releases ? relBody : '{"full_name":"demo-owner/demo-repo","private":false}');
            for (String k : cabecalhos.keySet()) r.setHeader(k, cabecalhos.get(k));
            return r;
        }
    }

    private static final String DUAS =
        '[{"tag_name":"v1.1.0","name":"RAIZ 1.1","published_at":"2026-10-20T12:00:00Z","html_url":"https://github.com/demo-owner/demo-repo/releases/tag/v1.1.0","body":"Notas","draft":false},' +
        '{"tag_name":"v1.0.0","name":"","published_at":"2026-10-19T12:00:00Z","html_url":"https://github.com/demo-owner/demo-repo/releases/tag/v1.0.0","body":null,"draft":false},' +
        '{"tag_name":"v9.9.9","name":"rascunho","draft":true}]';

    private static void configurar(Boolean ativo) {
        RaizGitHubService.configTeste = new RAIZ_Integracao__mdt(
            DeveloperName = 'RAIZ_GitHub',
            Owner__c = 'demo-owner',
            Repositorio__c = 'demo-repo',
            Named_Credential__c = 'RAIZ_GitHub',
            Ativo__c = ativo,
            Demonstracao__c = true
        );
    }

    private static RaizGitHubService.Resultado rodar(Mock m) {
        Test.setMock(HttpCalloutMock.class, m);
        return RaizGitHubService.sincronizar();
    }

    // Uma sincronizacao por metodo: Apex nao permite callout depois de DML na mesma transacao
    // (a propria classe faz todos os callouts antes de gravar).

    @IsTest
    static void sucessoGravaReleasesEIgnoraRascunho() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado r = rodar(new Mock(200, 200, DUAS));
        Test.stopTest();
        System.assertEquals('Sucesso', r.status, r.mensagem);
        System.assertEquals(2, r.encontradas, 'rascunho ignorado');
        System.assertEquals(2, r.criadas);
        System.assertEquals(2, [SELECT COUNT() FROM RAIZ_Release__c]);
        RAIZ_Release__c v100 = [SELECT Name, Publicada_Em__c, Fonte__c, Demonstracao__c FROM RAIZ_Release__c WHERE Tag__c = 'v1.0.0'];
        System.assertEquals('v1.0.0', v100.Name, 'sem nome usa a tag');
        System.assertEquals(DateTime.newInstanceGmt(2026, 10, 19, 12, 0, 0), v100.Publicada_Em__c);
        System.assertEquals('GitHub', v100.Fonte__c);
        System.assertEquals(true, v100.Demonstracao__c);
        RAIZ_Log_Execucao__c l = [SELECT Status__c, Codigo_HTTP__c, Mensagem__c FROM RAIZ_Log_Execucao__c WHERE Tipo__c = 'Integracao' LIMIT 1];
        System.assertEquals('Sucesso', l.Status__c);
        System.assertEquals(200, l.Codigo_HTTP__c);
        System.assert(!l.Mensagem__c.containsIgnoreCase('authorization') && !l.Mensagem__c.containsIgnoreCase('token'));
    }

    @IsTest
    static void sincronizarDeNovoAtualizaEmVezDeDuplicar() {
        configurar(true);
        insert new RAIZ_Release__c(Name = 'velha', Tag__c = 'v1.0.0', Fonte__c = 'Manual');
        Test.startTest();
        RaizGitHubService.Resultado r = rodar(new Mock(200, 200, DUAS));
        Test.stopTest();
        System.assertEquals(1, r.criadas);
        System.assertEquals(1, r.atualizadas);
        System.assertEquals(2, [SELECT COUNT() FROM RAIZ_Release__c]);
        System.assertEquals('GitHub', [SELECT Fonte__c FROM RAIZ_Release__c WHERE Tag__c = 'v1.0.0'].Fonte__c);
    }

    @IsTest
    static void codigosHttpViramMensagemClara() {
        Map<Integer, String> esperado = new Map<Integer, String>{
            401 => 'autenticação',
            404 => 'não encontrado',
            429 => 'Muitas requisições',
            500 => 'falha temporária',
            503 => 'falha temporária',
            418 => 'inesperada'
        };
        for (Integer s : esperado.keySet()) {
            HttpResponse h = new HttpResponse();
            h.setStatusCode(s);
            RaizGitHubService.Resultado r = RaizGitHubService.falha(new RaizGitHubService.Resultado(), h, 'o/r');
            System.assertEquals('Erro', r.status);
            System.assert(r.mensagem.contains(esperado.get(s)), s + ': ' + r.mensagem);
        }
        HttpResponse limite = new HttpResponse();
        limite.setStatusCode(403);
        limite.setHeader('X-RateLimit-Remaining', '0');
        limite.setHeader('X-RateLimit-Reset', '1792500000');
        String m = RaizGitHubService.falha(new RaizGitHubService.Resultado(), limite, 'o/r').mensagem;
        System.assert(m.contains('Limite de requisições') && m.contains('Liberação prevista'), m);
        HttpResponse negado = new HttpResponse();
        negado.setStatusCode(403);
        System.assert(RaizGitHubService.falha(new RaizGitHubService.Resultado(), negado, 'o/r').mensagem.contains('Acesso negado'));
    }

    @IsTest
    static void repositorioInexistenteRegistraLogSemGravar() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado r = rodar(new Mock(404, 200, DUAS));
        Test.stopTest();
        System.assertEquals('Erro', r.status);
        System.assertEquals(404, r.codigoHttp);
        System.assertEquals(0, [SELECT COUNT() FROM RAIZ_Release__c]);
        System.assertEquals(404, [SELECT Codigo_HTTP__c FROM RAIZ_Log_Execucao__c WHERE Tipo__c = 'Integracao'].Codigo_HTTP__c);
    }

    @IsTest
    static void falhaNaSegundaChamada() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado r = rodar(new Mock(200, 500, '{}'));
        Test.stopTest();
        System.assertEquals(500, r.codigoHttp);
        System.assertEquals(0, [SELECT COUNT() FROM RAIZ_Release__c]);
    }

    @IsTest
    static void timeoutNaoApagaOQueJaFoiSincronizado() {
        configurar(true);
        insert new RAIZ_Release__c(Name = 'antiga', Tag__c = 'v0.9.0', Fonte__c = 'GitHub');
        Mock lento = new Mock(200, 200, DUAS);
        lento.timeout = true;
        Test.startTest();
        RaizGitHubService.Resultado t = rodar(lento);
        Test.stopTest();
        System.assertEquals('Erro', t.status);
        System.assert(t.mensagem.contains('indisponível'), t.mensagem);
        System.assertEquals(1, [SELECT COUNT() FROM RAIZ_Release__c]);
    }

    @IsTest
    static void jsonInvalidoNaoCopiaOCorpo() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado j = rodar(new Mock(200, 200, 'isto nao e json'));
        Test.stopTest();
        System.assertEquals('Erro', j.status);
        System.assert(!j.mensagem.contains('isto nao e json'));
    }

    @IsTest
    static void respostaQueNaoELista() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado o = rodar(new Mock(200, 200, '{"message":"x"}'));
        Test.stopTest();
        System.assertEquals('Erro', o.status);
    }

    @IsTest
    static void repositorioSemReleases() {
        configurar(true);
        Test.startTest();
        RaizGitHubService.Resultado v = rodar(new Mock(200, 200, '[]'));
        Test.stopTest();
        System.assertEquals('Ignorado', v.status);
        System.assert(v.mensagem.contains('sem releases'));
    }

    @IsTest
    static void desativadaNaoChamaOGitHub() {
        configurar(false);
        Mock m = new Mock(200, 200, DUAS);
        Test.setMock(HttpCalloutMock.class, m);
        RaizGitHubService.Resultado r = RaizGitHubService.sincronizar();
        System.assertEquals('Ignorado', r.status);
        System.assertEquals(0, m.chamadas);
        System.assertEquals(1, [SELECT COUNT() FROM RAIZ_Log_Execucao__c WHERE Tipo__c = 'Integracao' AND Status__c = 'Ignorado']);
    }

    @IsTest
    static void estadoMostraSeAReleaseFoiImplantada() {
        configurar(true);
        RAIZ_Release__c a = new RAIZ_Release__c(Name = 'RAIZ 1.0', Tag__c = 'v1.0.0', Fonte__c = 'GitHub', Publicada_Em__c = DateTime.now());
        RAIZ_Release__c b = new RAIZ_Release__c(Name = 'RAIZ 1.1', Tag__c = 'v1.1.0', Fonte__c = 'GitHub', Publicada_Em__c = DateTime.now().addDays(-1));
        insert new List<RAIZ_Release__c>{ a, b };
        insert new RAIZ_Implantacao__c(Deploy_Id__c = '0AfTESTE000000009', Resultado__c = 'Sucesso', Release__c = a.Id, Origem__c = 'sf CLI');
        RaizTestData.criarUsuarios();
        RaizGitHubService.Estado e;
        System.runAs(RaizTestData.usuarioRaiz()) {
            e = RaizGitHubService.getEstado();
        }
        System.assertEquals(null, e.erro, 'estado sem erro: ' + String.valueOf(e.erro));
        System.assertEquals('demo-owner', e.config.owner);
        System.assertEquals('https://github.com/demo-owner/demo-repo', e.config.urlPublica);
        System.assertEquals(2, e.releases.size());
        Map<String, RaizGitHubService.ReleaseInfo> m = new Map<String, RaizGitHubService.ReleaseInfo>();
        for (RaizGitHubService.ReleaseInfo i : e.releases) m.put(i.tag, i);
        System.assertEquals(true, m.get('v1.0.0').implantada);
        System.assertEquals(false, m.get('v1.1.0').implantada, 'release publicada sem deploy não conta como implantada');
    }
}
