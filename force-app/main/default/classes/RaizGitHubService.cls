/**
 * RaizGitHubService — RAIZ Integration Hub (Onda 9): leitura da API REST oficial do GitHub.
 * ---------------------------------------------------------------------------
 * SOMENTE LEITURA (ADR-016). Nunca cria commit, issue ou release.
 *
 *   sincronizar()  GET /repos/{owner}/{repo}            -> o repositorio existe e e publico?
 *                  GET /repos/{owner}/{repo}/releases   -> releases publicadas
 *                  upsert em RAIZ_Release__c por Tag__c (rodar de novo nao duplica)
 *   getEstado()    o que a tela mostra: configuracao, releases ja gravadas,
 *                  se cada release tem implantacao registrada, ultimas execucoes
 *
 * POR QUE A TELA LE DA SALESFORCE E NAO DO GITHUB: a leitura anonima do GitHub tem
 * limite baixo por IP de origem, e os IPs de saida da Salesforce sao compartilhados.
 * A sincronizacao e manual; se o GitHub falhar, os dados ja sincronizados continuam.
 *
 * RELEASE NAO E IMPLANTACAO (ADR-017): "implantada" so e verdadeiro quando existe
 * RAIZ_Implantacao__c ligada a release (deploy real, registrado pelo sf CLI).
 *
 * CONFIGURACAO: RAIZ_Integracao__mdt.RAIZ_GitHub (dono, repositorio, Named Credential).
 * Sem segredo: o repositorio e publico. Para subir o limite, trocar por External
 * Credential com token somente leitura (digitado no Setup, nunca no codigo).
 * LOG: RaizLog, tipo Integracao, com o codigo HTTP; nunca grava corpo bruto nem cabecalho.
 */
public with sharing class RaizGitHubService {
    public static final String CONFIG = 'RAIZ_GitHub';
    public static final Integer TIMEOUT_MS = 10000;

    @TestVisible
    private static RAIZ_Integracao__mdt configTeste;

    public class Config {
        @AuraEnabled
        public String owner;
        @AuraEnabled
        public String repositorio;
        @AuraEnabled
        public String credencial;
        @AuraEnabled
        public Boolean ativo = false;
        @AuraEnabled
        public Boolean demonstracao = false;
        @AuraEnabled
        public String urlPublica;
    }

    public class Resultado {
        @AuraEnabled
        public String status; // Sucesso | Ignorado | Erro
        @AuraEnabled
        public String mensagem;
        @AuraEnabled
        public Integer codigoHttp;
        @AuraEnabled
        public Integer encontradas = 0;
        @AuraEnabled
        public Integer criadas = 0;
        @AuraEnabled
        public Integer atualizadas = 0;
        @AuraEnabled
        public DateTime quando;
    }

    public class ReleaseInfo {
        @AuraEnabled
        public String tag;
        @AuraEnabled
        public String nome;
        @AuraEnabled
        public DateTime publicadaEm;
        @AuraEnabled
        public String url;
        @AuraEnabled
        public Boolean demonstracao = false;
        @AuraEnabled
        public DateTime sincronizadoEm;
        @AuraEnabled
        public Integer implantacoes = 0;
        @AuraEnabled
        public Boolean implantada = false;
    }

    public class Execucao {
        @AuraEnabled
        public DateTime quando;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer codigoHttp;
        @AuraEnabled
        public String mensagem;
        @AuraEnabled
        public Integer execucoes;
    }

    public class Estado {
        @AuraEnabled
        public Config config;
        @AuraEnabled
        public List<ReleaseInfo> releases = new List<ReleaseInfo>();
        @AuraEnabled
        public List<Execucao> execucoes = new List<Execucao>();
        @AuraEnabled
        public String erro;
    }

    // ============================================================ config
    public static Config config() {
        RAIZ_Integracao__mdt m = Test.isRunningTest() && configTeste != null ? configTeste : RAIZ_Integracao__mdt.getInstance(CONFIG);
        if (m == null) return null;
        Config c = new Config();
        c.owner = m.Owner__c;
        c.repositorio = m.Repositorio__c;
        c.credencial = m.Named_Credential__c;
        c.ativo = m.Ativo__c == true;
        c.demonstracao = m.Demonstracao__c == true;
        if (c.owner != null && c.repositorio != null) c.urlPublica = 'https://github.com/' + c.owner + '/' + c.repositorio;
        return c;
    }

    // ======================================================= sincronizar
    @AuraEnabled
    public static Resultado sincronizar() {
        Resultado r = new Resultado();
        r.quando = DateTime.now();
        if (!Schema.SObjectType.RAIZ_Release__c.isCreateable()) {
            r.status = 'Erro';
            r.mensagem = 'Sem permissão para gravar releases: sincronizar exige o permission set RAIZ_Engenharia.';
            return registrar(r);
        }
        Config c = config();
        if (c == null || !c.ativo || String.isBlank(c.owner) || String.isBlank(c.repositorio) || String.isBlank(c.credencial)) {
            r.status = 'Ignorado';
            r.mensagem = 'Integração desativada ou sem configuração completa (RAIZ_Integracao__mdt.RAIZ_GitHub). Nenhuma chamada feita.';
            return registrar(r);
        }
        String repo = c.owner + '/' + c.repositorio;
        String base = 'callout:' + c.credencial + '/repos/' + EncodingUtil.urlEncode(c.owner, 'UTF-8') + '/' + EncodingUtil.urlEncode(c.repositorio, 'UTF-8');
        List<RAIZ_Release__c> recs = new List<RAIZ_Release__c>();
        try {
            HttpResponse rr = get(base);
            r.codigoHttp = rr.getStatusCode();
            if (rr.getStatusCode() != 200) return registrar(falha(r, rr, repo));
            HttpResponse rel = get(base + '/releases?per_page=30');
            r.codigoHttp = rel.getStatusCode();
            if (rel.getStatusCode() != 200) return registrar(falha(r, rel, repo));
            List<Object> lista;
            try {
                lista = (List<Object>) JSON.deserializeUntyped(rel.getBody());
            } catch (Exception e) {
                r.status = 'Erro';
                r.mensagem = 'Resposta do GitHub em formato inesperado (JSON inválido ou não é lista). Nada foi gravado.';
                return registrar(r);
            }
            for (Object o : lista) {
                if (!(o instanceof Map<String, Object>)) continue;
                Map<String, Object> m = (Map<String, Object>) o;
                String tag = (String) m.get('tag_name');
                if (String.isBlank(tag) || m.get('draft') == true) continue;
                String nome = String.isBlank((String) m.get('name')) ? tag : (String) m.get('name');
                String corpo = (String) m.get('body');
                recs.add(
                    new RAIZ_Release__c(
                        Name = nome.left(80),
                        Tag__c = tag.left(100),
                        Publicada_Em__c = dataHora((String) m.get('published_at')),
                        URL__c = ((String) m.get('html_url')),
                        Resumo__c = corpo == null ? null : corpo.left(5000),
                        Fonte__c = 'GitHub',
                        Demonstracao__c = c.demonstracao,
                        Sincronizado_Em__c = r.quando
                    )
                );
            }
        } catch (CalloutException e) {
            r.status = 'Erro';
            r.mensagem = 'GitHub indisponível ou sem resposta em ' + (TIMEOUT_MS / 1000) + ' s. Os dados já sincronizados continuam na org. Detalhe: ' + e.getMessage();
            return registrar(r);
        }
        // DML so depois de todos os callouts.
        r.encontradas = recs.size();
        if (recs.isEmpty()) {
            r.status = 'Ignorado';
            r.mensagem = 'Repositório ' + repo + ' encontrado, mas sem releases publicadas.';
            return registrar(r);
        }
        List<Database.UpsertResult> urs = Database.upsert(recs, RAIZ_Release__c.Tag__c, false);
        List<String> erros = new List<String>();
        for (Integer i = 0; i < urs.size(); i++) {
            if (!urs[i].isSuccess()) {
                erros.add(recs[i].Tag__c + ': ' + urs[i].getErrors()[0].getMessage());
            } else if (urs[i].isCreated()) {
                r.criadas++;
            } else {
                r.atualizadas++;
            }
        }
        r.status = erros.isEmpty() ? 'Sucesso' : 'Erro';
        r.mensagem =
            repo + ': ' + r.encontradas + ' releases lidas; ' + r.criadas + ' novas; ' + r.atualizadas + ' atualizadas' +
            (erros.isEmpty() ? '.' : '; falhas: ' + String.join(erros, ' | ').left(1000));
        return registrar(r);
    }

    private static HttpResponse get(String endpoint) {
        HttpRequest q = new HttpRequest();
        q.setEndpoint(endpoint);
        q.setMethod('GET');
        q.setTimeout(TIMEOUT_MS);
        q.setHeader('Accept', 'application/vnd.github+json');
        q.setHeader('X-GitHub-Api-Version', '2022-11-28');
        q.setHeader('User-Agent', 'RAIZ-Salesforce-Integration-Hub');
        return new Http().send(q);
    }

    @TestVisible
    private static Resultado falha(Resultado r, HttpResponse h, String repo) {
        Integer s = h.getStatusCode();
        r.status = 'Erro';
        if (s == 404) {
            r.mensagem = 'Repositório ' + repo + ' não encontrado ou não é público (404).';
        } else if (s == 401) {
            r.mensagem = 'GitHub recusou a autenticação (401). A leitura anônima não deveria pedir credencial: confira a Named Credential.';
        } else if (s == 403 && h.getHeader('X-RateLimit-Remaining') == '0') {
            r.mensagem = 'Limite de requisições anônimas do GitHub atingido (403). Os IPs da Salesforce são compartilhados; tente mais tarde.' + liberaEm(h);
        } else if (s == 403) {
            r.mensagem = 'Acesso negado pelo GitHub (403).';
        } else if (s == 429) {
            r.mensagem = 'Muitas requisições ao GitHub (429). Tente mais tarde.' + liberaEm(h);
        } else if (s >= 500) {
            r.mensagem = 'GitHub com falha temporária (' + s + '). Os dados já sincronizados continuam na org.';
        } else {
            r.mensagem = 'Resposta inesperada do GitHub (' + s + ').';
        }
        return r;
    }

    private static String liberaEm(HttpResponse h) {
        String reset = h.getHeader('X-RateLimit-Reset');
        if (String.isBlank(reset) || !reset.isNumeric()) return '';
        return ' Liberação prevista: ' + DateTime.newInstance(Long.valueOf(reset) * 1000).format() + '.';
    }

    private static DateTime dataHora(String iso) {
        if (String.isBlank(iso)) return null;
        try {
            return (DateTime) JSON.deserialize('"' + iso + '"', DateTime.class);
        } catch (Exception e) {
            return null;
        }
    }

    private static Resultado registrar(Resultado r) {
        RaizLog.registrar(
            'Integracao',
            'sincronizacao GitHub',
            r.status,
            null,
            'GITHUB:' + r.quando.getTime() + ':' + Crypto.getRandomInteger(),
            r.mensagem,
            r.codigoHttp
        );
        return r;
    }

    // ============================================================ estado
    @AuraEnabled
    public static Estado getEstado() {
        Estado e = new Estado();
        try {
            e.config = config();
            Map<Id, ReleaseInfo> porId = new Map<Id, ReleaseInfo>();
            for (RAIZ_Release__c r : [
                SELECT Id, Name, Tag__c, Publicada_Em__c, URL__c, Demonstracao__c, Sincronizado_Em__c
                FROM RAIZ_Release__c
                WITH USER_MODE
                ORDER BY Publicada_Em__c DESC NULLS LAST
                LIMIT 50
            ]) {
                ReleaseInfo i = new ReleaseInfo();
                i.tag = r.Tag__c;
                i.nome = r.Name;
                i.publicadaEm = r.Publicada_Em__c;
                i.url = r.URL__c;
                i.demonstracao = r.Demonstracao__c == true;
                i.sincronizadoEm = r.Sincronizado_Em__c;
                porId.put(r.Id, i);
                e.releases.add(i);
            }
            if (!porId.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Release__c rel, COUNT(Id) n
                    FROM RAIZ_Implantacao__c
                    WHERE Release__c IN :porId.keySet() AND Resultado__c = 'Sucesso'
                    WITH USER_MODE
                    GROUP BY Release__c
                ]) {
                    ReleaseInfo i = porId.get((Id) ar.get('rel'));
                    i.implantacoes = (Integer) ar.get('n');
                    i.implantada = i.implantacoes > 0;
                }
            }
            for (RAIZ_Log_Execucao__c l : [
                SELECT Executado_Em__c, Status__c, Codigo_HTTP__c, Mensagem__c, Execucoes__c
                FROM RAIZ_Log_Execucao__c
                WHERE Tipo__c = 'Integracao'
                WITH USER_MODE
                ORDER BY Executado_Em__c DESC
                LIMIT 10
            ]) {
                Execucao x = new Execucao();
                x.quando = l.Executado_Em__c;
                x.status = l.Status__c;
                x.codigoHttp = l.Codigo_HTTP__c == null ? null : l.Codigo_HTTP__c.intValue();
                x.mensagem = l.Mensagem__c;
                x.execucoes = l.Execucoes__c == null ? 1 : l.Execucoes__c.intValue();
                e.execucoes.add(x);
            }
        } catch (Exception ex) {
            e.erro = 'Integração indisponível: ' + ex.getMessage();
        }
        return e;
    }
}
