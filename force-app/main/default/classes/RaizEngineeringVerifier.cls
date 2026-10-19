/**
 * RaizEngineeringVerifier — confere na org o que o inventario de engenharia declara (Onda 8).
 * ---------------------------------------------------------------------------
 * Regra central (ADR-015): preencher um item NAO o valida. Estado_Validacao__c
 * so e gravado aqui, a partir do que a propria org responde:
 *
 *   Objeto / Campo        Schema (describe)
 *   Classe Apex / Trigger ApexClass, ApexTrigger (Status Active)
 *   Flow                  FlowDefinitionView (IsActive)
 *   Permission Set        PermissionSet
 *   Job agendado          CronTrigger (CronJobDetail.Name)
 *   Aba / App             TabDefinition / AppMenuItem
 *   Notificacao           CustomNotificationType
 *   Named Credential      NamedCredential
 *   LWC                   Apex nao enxerga LightningComponentBundle: so fica
 *                         "Verificado" se houver evidencia do sf CLI dos ultimos 7 dias
 *   Teste_Associado__c    ultima execucao registrada (ApexTestResult) sem falha
 *
 * Funcionalidade: Verificado se TODOS os componentes estao Verificados; Falhou se
 * algum falhou; sem componentes ou com componente nao verificavel = Nao verificavel.
 * Item "Planejado" nao e verificado (continua Declarado).
 *
 * without sharing (ADR-018): le metadados de seguranca e grava evidencias que o
 * usuario comum so le. Nunca altera o que o item declara.
 */
public without sharing class RaizEngineeringVerifier {
    public static final String ORIGEM = 'Verificador Apex';
    public static final Integer DIAS_CLI = 7;

    public class Resultado {
        @AuraEnabled
        public Integer total = 0;
        @AuraEnabled
        public Integer verificados = 0;
        @AuraEnabled
        public Integer falhas = 0;
        @AuraEnabled
        public Integer naoVerificaveis = 0;
        @AuraEnabled
        public Integer planejados = 0;
        @AuraEnabled
        public DateTime quando;
    }

    @AuraEnabled
    public static Resultado verificar() {
        try {
            return executar();
        } catch (Exception e) {
            AuraHandledException a = new AuraHandledException('Verificação não concluída: ' + e.getMessage());
            a.setMessage('Verificação não concluída: ' + e.getMessage());
            throw a;
        }
    }

    public static Resultado executar() {
        Resultado r = new Resultado();
        r.quando = DateTime.now();
        List<RAIZ_Engineering_Status__c> itens = [
            SELECT Id, Name, API_Name__c, Tipo_Componente__c, Teste_Associado__c, Nivel__c, Funcionalidade__c, Status_Implementacao__c
            FROM RAIZ_Engineering_Status__c
            LIMIT 2000
        ];
        Set<String> nomes = new Set<String>();
        for (RAIZ_Engineering_Status__c i : itens) {
            if (i.API_Name__c != null) nomes.add(i.API_Name__c);
            if (i.Teste_Associado__c != null) nomes.add(i.Teste_Associado__c);
        }
        Catalogo cat = new Catalogo(nomes);

        Map<Id, String> estado = new Map<Id, String>();
        Map<Id, String> detalhe = new Map<Id, String>();
        List<RAIZ_Evidencia__c> evid = new List<RAIZ_Evidencia__c>();
        List<RAIZ_Engineering_Status__c> funcionalidades = new List<RAIZ_Engineering_Status__c>();

        for (RAIZ_Engineering_Status__c i : itens) {
            if (i.Nivel__c == 'Funcionalidade') {
                funcionalidades.add(i);
                continue;
            }
            if (i.Status_Implementacao__c == 'Planejado') {
                estado.put(i.Id, 'Declarado');
                detalhe.put(i.Id, 'Planejado: nada a verificar ainda.');
                continue;
            }
            Achado meta = cat.conferir(i.Tipo_Componente__c, i.API_Name__c, i.Id);
            List<String> partes = new List<String>{ meta.texto };
            String est;
            if (meta.verificavel) {
                evid.add(evidencia(i, 'Metadado na org', meta.ok, meta.texto, r.quando));
                est = meta.ok ? 'Verificado' : 'Falhou';
            } else {
                est = meta.ok ? 'Verificado' : 'Nao verificavel';
            }
            if (i.Teste_Associado__c != null) {
                Achado t = cat.teste(i.Teste_Associado__c);
                partes.add(t.texto);
                if (t.verificavel) evid.add(evidencia(i, 'Teste Apex', t.ok, t.texto, r.quando));
                if (!t.ok && est != 'Falhou') est = t.verificavel ? 'Falhou' : est;
            }
            estado.put(i.Id, est);
            detalhe.put(i.Id, String.join(partes, ' '));
        }

        // Funcionalidade = soma dos seus componentes.
        Map<Id, List<String>> filhos = new Map<Id, List<String>>();
        for (RAIZ_Engineering_Status__c i : itens) {
            if (i.Funcionalidade__c == null || i.Nivel__c == 'Funcionalidade') continue;
            if (!filhos.containsKey(i.Funcionalidade__c)) filhos.put(i.Funcionalidade__c, new List<String>());
            filhos.get(i.Funcionalidade__c).add(estado.get(i.Id));
        }
        for (RAIZ_Engineering_Status__c f : funcionalidades) {
            List<String> es = filhos.containsKey(f.Id) ? filhos.get(f.Id) : new List<String>();
            Integer ok = 0;
            Integer falhou = 0;
            for (String s : es) {
                if (s == 'Verificado') ok++;
                if (s == 'Falhou') falhou++;
            }
            String est;
            if (f.Status_Implementacao__c == 'Planejado') est = 'Declarado';
            else if (es.isEmpty()) est = 'Nao verificavel';
            else if (falhou > 0) est = 'Falhou';
            else if (ok == es.size()) est = 'Verificado';
            else est = 'Nao verificavel';
            estado.put(f.Id, est);
            detalhe.put(
                f.Id,
                f.Status_Implementacao__c == 'Planejado'
                    ? 'Planejado: nada a verificar ainda.'
                    : ok + ' de ' + es.size() + ' componentes verificados' + (falhou > 0 ? '; ' + falhou + ' com falha.' : '.')
            );
        }

        List<RAIZ_Engineering_Status__c> upd = new List<RAIZ_Engineering_Status__c>();
        for (RAIZ_Engineering_Status__c i : itens) {
            String est = estado.get(i.Id);
            r.total++;
            if (est == 'Verificado') r.verificados++;
            else if (est == 'Falhou') r.falhas++;
            else if (est == 'Nao verificavel') r.naoVerificaveis++;
            else r.planejados++;
            upd.add(
                new RAIZ_Engineering_Status__c(
                    Id = i.Id,
                    Estado_Validacao__c = est,
                    Ultima_Verificacao__c = r.quando,
                    Origem_Verificacao__c = i.Tipo_Componente__c == 'LWC' ? 'sf CLI (evidência) + Verificador Apex' : ORIGEM,
                    Resultado_Verificacao__c = detalhe.get(i.Id) == null ? null : detalhe.get(i.Id).left(2000)
                )
            );
        }
        if (!evid.isEmpty()) Database.upsert(evid, RAIZ_Evidencia__c.Chave__c, true);
        update upd;
        RaizLog.registrar(
            'Verificacao',
            'verificacao',
            r.falhas > 0 ? 'Bloqueado' : 'Sucesso',
            null,
            'VERIFICACAO:' + r.quando.getTime(),
            'Itens: ' + r.total + '. Verificados: ' + r.verificados + '. Falhas: ' + r.falhas + '. Não verificáveis: ' +
            r.naoVerificaveis + '. Planejados: ' + r.planejados + '. Evidências gravadas: ' + evid.size() + '.'
        );
        return r;
    }

    private static RAIZ_Evidencia__c evidencia(RAIZ_Engineering_Status__c i, String tipo, Boolean ok, String texto, DateTime quando) {
        return new RAIZ_Evidencia__c(
            Item__c = i.Id,
            Tipo__c = tipo,
            Origem__c = ORIGEM,
            Resultado__c = ok ? 'Aprovado' : 'Reprovado',
            Detalhe__c = texto == null ? null : texto.left(255),
            Verificado_Em__c = quando,
            Chave__c = (i.API_Name__c + '|' + tipo + '|' + ORIGEM).left(255)
        );
    }

    // ================================================================ catalogo
    public class Achado {
        public Boolean ok = false;
        public Boolean verificavel = true;
        public String texto;
        public Achado(Boolean ok, Boolean verificavel, String texto) {
            this.ok = ok;
            this.verificavel = verificavel;
            this.texto = texto;
        }
    }

    /** Carrega uma vez, em poucas consultas, tudo o que o inventario cita. */
    public class Catalogo {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Set<String> classes = new Set<String>();
        Map<String, String> triggers = new Map<String, String>();
        Map<String, Boolean> flows = new Map<String, Boolean>();
        Set<String> permsets = new Set<String>();
        Set<String> jobs = new Set<String>();
        Set<String> abas = new Set<String>();
        Set<String> apps = new Set<String>();
        Set<String> notificacoes = new Set<String>();
        Set<String> credenciais = new Set<String>();
        Set<Id> comCliRecente = new Set<Id>();
        Map<String, List<ApexTestResult>> testes = new Map<String, List<ApexTestResult>>();

        public Catalogo(Set<String> nomes) {
            for (ApexClass c : [SELECT Name FROM ApexClass WHERE Name IN :nomes]) classes.add(c.Name);
            for (ApexTrigger t : [SELECT Name, Status FROM ApexTrigger WHERE Name IN :nomes]) triggers.put(t.Name, t.Status);
            for (FlowDefinitionView f : [SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName IN :nomes]) flows.put(f.ApiName, f.IsActive);
            for (PermissionSet p : [SELECT Name FROM PermissionSet WHERE Name IN :nomes]) permsets.add(p.Name);
            for (CronTrigger c : [SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name IN :nomes]) jobs.add(c.CronJobDetail.Name);
            for (TabDefinition t : [SELECT Name FROM TabDefinition WHERE Name IN :nomes]) abas.add(t.Name);
            for (AppMenuItem a : [SELECT Name FROM AppMenuItem WHERE Name IN :nomes]) apps.add(a.Name);
            for (CustomNotificationType n : [SELECT DeveloperName FROM CustomNotificationType WHERE DeveloperName IN :nomes]) {
                notificacoes.add(n.DeveloperName);
            }
            for (NamedCredential n : [SELECT DeveloperName FROM NamedCredential WHERE DeveloperName IN :nomes]) credenciais.add(n.DeveloperName);
            DateTime corte = DateTime.now().addDays(-DIAS_CLI);
            for (RAIZ_Evidencia__c e : [
                SELECT Item__c
                FROM RAIZ_Evidencia__c
                WHERE Origem__c = 'sf CLI' AND Resultado__c = 'Aprovado' AND Tipo__c = 'Metadado na org' AND Verificado_Em__c >= :corte
            ]) {
                comCliRecente.add(e.Item__c);
            }
            for (ApexTestResult t : [
                SELECT ApexClass.Name, MethodName, Outcome, AsyncApexJobId, TestTimestamp
                FROM ApexTestResult
                WHERE ApexClass.Name IN :nomes
                ORDER BY TestTimestamp DESC
                LIMIT 3000
            ]) {
                if (!testes.containsKey(t.ApexClass.Name)) testes.put(t.ApexClass.Name, new List<ApexTestResult>());
                testes.get(t.ApexClass.Name).add(t);
            }
        }

        public Achado conferir(String tipo, String api, Id itemId) {
            if (String.isBlank(api)) return new Achado(false, true, 'Sem nome de API.');
            switch on tipo {
                when 'Objeto' {
                    Boolean ok = gd.containsKey(api.toLowerCase());
                    return new Achado(ok, true, ok ? 'Objeto existe.' : 'Objeto não encontrado.');
                }
                when 'Campo' {
                    List<String> p = api.split('\\.');
                    Boolean ok =
                        p.size() == 2 &&
                        gd.containsKey(p[0].toLowerCase()) &&
                        gd.get(p[0].toLowerCase()).getDescribe().fields.getMap().containsKey(p[1].toLowerCase());
                    return new Achado(ok, true, ok ? 'Campo existe.' : 'Campo não encontrado.');
                }
                when 'Classe Apex' {
                    Boolean ok = classes.contains(api);
                    return new Achado(ok, true, ok ? 'Classe existe.' : 'Classe não encontrada.');
                }
                when 'Trigger' {
                    Boolean ok = triggers.get(api) == 'Active';
                    return new Achado(ok, true, triggers.containsKey(api) ? 'Trigger ' + triggers.get(api) + '.' : 'Trigger não encontrado.');
                }
                when 'Flow' {
                    Boolean ok = flows.get(api) == true;
                    return new Achado(ok, true, flows.containsKey(api) ? (ok ? 'Flow ativo.' : 'Flow inativo.') : 'Flow não encontrado.');
                }
                when 'Permission Set' {
                    Boolean ok = permsets.contains(api);
                    return new Achado(ok, true, ok ? 'Permission set existe.' : 'Permission set não encontrado.');
                }
                when 'Job agendado' {
                    Boolean ok = jobs.contains(api);
                    return new Achado(ok, true, ok ? 'Job agendado.' : 'Job não agendado.');
                }
                when 'Aba' {
                    Boolean ok = abas.contains(api);
                    return new Achado(ok, true, ok ? 'Aba existe.' : 'Aba não encontrada.');
                }
                when 'App' {
                    Boolean ok = apps.contains(api);
                    return new Achado(ok, true, ok ? 'App existe.' : 'App não encontrado.');
                }
                when 'Notificacao' {
                    Boolean ok = notificacoes.contains(api);
                    return new Achado(ok, true, ok ? 'Tipo de notificação existe.' : 'Tipo de notificação não encontrado.');
                }
                when 'Named Credential' {
                    Boolean ok = credenciais.contains(api);
                    return new Achado(ok, true, ok ? 'Named Credential existe.' : 'Named Credential não encontrada.');
                }
                when 'LWC' {
                    Boolean ok = comCliRecente.contains(itemId);
                    return new Achado(
                        ok,
                        false,
                        ok ? 'Componente confirmado pelo sf CLI nos últimos ' + DIAS_CLI + ' dias.' : 'Apex não enxerga LWC: rode registrar-evidencias.sh.'
                    );
                }
                when else {
                    return new Achado(false, false, 'Tipo sem verificação automática.');
                }
            }
        }

        /** Ultima execucao registrada da classe de teste: todos os metodos dessa execucao passaram? */
        public Achado teste(String classe) {
            List<ApexTestResult> rs = testes.get(classe);
            if (rs == null || rs.isEmpty()) return new Achado(false, false, 'Sem execução registrada de ' + classe + '.');
            Id job = rs[0].AsyncApexJobId;
            Integer total = 0;
            Integer passou = 0;
            for (ApexTestResult t : rs) {
                if (t.AsyncApexJobId != job) continue;
                total++;
                if (t.Outcome == 'Pass') passou++;
            }
            Boolean ok = total > 0 && passou == total;
            return new Achado(ok, true, classe + ': ' + passou + '/' + total + ' métodos aprovados na última execução (' + rs[0].TestTimestamp.format() + ').');
        }
    }
}
