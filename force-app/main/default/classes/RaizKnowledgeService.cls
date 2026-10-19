/**
 * RaizKnowledgeService — Knowledge Hub do Metodo RAIZ (Onda 5).
 * ---------------------------------------------------------------------------
 * Reaproveita o Documento Funcional (Business_Rule__c) — decisao D2a: sem
 * ativar o Salesforce Knowledge. O ciclo do documento vira um quadro:
 *
 *   Backlog        processo critico sem nenhum documento
 *   Em elaboracao  Status Draft
 *   Em revisao     Status Em Analise
 *   Aprovado       Status Aprovada      (exige permissao RAIZ_Aprovar_Documentos)
 *   Publicado      Status Publicada     (idem; atualiza o registro do processo)
 *
 * REGRAS
 *   - O quadro mostra so documentos ligados a um Processo_Critico__c.
 *   - Avancar/voltar e uma etapa por vez, por clique explicito.
 *   - Quem escreve nao aprova: Aprovada e Publicada exigem a permissao
 *     personalizada RAIZ_Aprovar_Documentos.
 *   - O conteudo minimo e cobrado no Apex (e tambem pela regra de validacao
 *     Conteudo_Minimo_Aprovado, quando ativa); o quadro antecipa as pendencias.
 *   - Publicar marca o processo como Registrado com revisao hoje — e isso que
 *     faz a Atualidade do acervo e a Cobertura critica reagirem.
 *
 * SEGURANCA: with sharing; leituras WITH USER_MODE; escritas AccessLevel.USER_MODE.
 */
public with sharing class RaizKnowledgeService {
    public static final String PERMISSAO_APROVAR = 'RAIZ_Aprovar_Documentos';
    public static final String PROJETO_RAIZ = 'RAIZ - Base de conhecimento';

    public static final String BACKLOG = 'Backlog';
    public static final List<String> FLUXO = new List<String>{ 'Draft', 'Em Analise', 'Aprovada', 'Publicada' };
    private static final Map<String, String> ROTULO_COLUNA = new Map<String, String>{
        'Draft' => 'Em elaboração',
        'Em Analise' => 'Em revisão',
        'Aprovada' => 'Aprovado',
        'Publicada' => 'Publicado'
    };
    private static final Set<String> EXIGE_APROVADOR = new Set<String>{ 'Aprovada', 'Publicada' };

    // ================================================================ DTOs
    public class Cartao {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id processoId;
        @AuraEnabled
        public String titulo;
        @AuraEnabled
        public String processo;
        @AuraEnabled
        public String criticidade;
        @AuraEnabled
        public String estadoCobertura;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Date ultimaRevisao;
        @AuraEnabled
        public Integer demandasLigadas = 0;
        @AuraEnabled
        public List<String> pendencias = new List<String>();
        @AuraEnabled
        public Boolean podeAvancar = false;
        @AuraEnabled
        public Boolean podeVoltar = false;
        @AuraEnabled
        public String proximaEtapa;
        @AuraEnabled
        public String motivoBloqueio;
        // Onda 7 — situacao gravada pela automacao de governanca
        @AuraEnabled
        public String governanca;
        @AuraEnabled
        public Date prazoRevisao;
    }

    public class Coluna {
        @AuraEnabled
        public String chave;
        @AuraEnabled
        public String rotulo;
        @AuraEnabled
        public List<Cartao> cartoes = new List<Cartao>();
        @AuraEnabled
        public Integer total = 0;
    }

    public class Quadro {
        @AuraEnabled
        public Boolean podeAprovar = false;
        @AuraEnabled
        public List<Coluna> colunas = new List<Coluna>();
        @AuraEnabled
        public Integer documentos = 0;
        @AuraEnabled
        public Integer publicados = 0;
        @AuraEnabled
        public Integer processosSemDocumento = 0;
        @AuraEnabled
        public List<String> premissas = new List<String>();
    }

    // ============================================================ leitura
    @AuraEnabled(cacheable=true)
    public static Quadro getQuadro(Id contaId) {
        try {
            return montar(contaId);
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    public static Boolean podeAprovar() {
        return FeatureManagement.checkPermission(PERMISSAO_APROVAR);
    }

    private static Quadro montar(Id contaId) {
        Quadro q = new Quadro();
        q.podeAprovar = podeAprovar();
        q.premissas.add('Só entram documentos ligados a um processo crítico.');
        q.premissas.add('Aprovar e publicar exigem a permissão "RAIZ - Aprovar documentos": quem escreve não aprova sozinho.');
        q.premissas.add('Publicar marca o processo como Registrado, com revisão hoje.');

        Map<String, Coluna> cols = new Map<String, Coluna>();
        Coluna colBacklog = new Coluna();
        colBacklog.chave = BACKLOG;
        colBacklog.rotulo = 'Backlog';
        q.colunas.add(colBacklog);
        for (String st : FLUXO) {
            Coluna c = new Coluna();
            c.chave = st;
            c.rotulo = ROTULO_COLUNA.get(st);
            cols.put(st, c);
            q.colunas.add(c);
        }

        List<Processo_Critico__c> procs = (contaId == null)
            ? [
                  SELECT Id, Name, Criticidade__c, Estado_Cobertura__c, Risco_Score__c
                  FROM Processo_Critico__c
                  WITH USER_MODE
                  ORDER BY Risco_Score__c DESC NULLS LAST
                  LIMIT 2000
              ]
            : [
                  SELECT Id, Name, Criticidade__c, Estado_Cobertura__c, Risco_Score__c
                  FROM Processo_Critico__c
                  WHERE Conta__c = :contaId
                  WITH USER_MODE
                  ORDER BY Risco_Score__c DESC NULLS LAST
                  LIMIT 2000
              ];
        Map<Id, Processo_Critico__c> porId = new Map<Id, Processo_Critico__c>(procs);

        List<Business_Rule__c> docs = [
            SELECT
                Id,
                Title__c,
                Status__c,
                Last_Review_Date__c,
                Processo_Critico__c,
                Proposito_Documento__c,
                Descricao_Demanda__c,
                Criterios_Aceite__c,
                Cenarios_Teste__c,
                Governanca_Status__c,
                Prazo_Revisao__c
            FROM Business_Rule__c
            WHERE Processo_Critico__c IN :porId.keySet() AND Status__c IN :FLUXO
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 2000
        ];

        Map<Id, Integer> demandas = contarDemandas(docs);
        Set<Id> comDoc = new Set<Id>();
        for (Business_Rule__c d : docs) {
            comDoc.add(d.Processo_Critico__c);
            Cartao k = cartao(d, porId.get(d.Processo_Critico__c), q.podeAprovar);
            k.demandasLigadas = demandas.containsKey(d.Id) ? demandas.get(d.Id) : 0;
            cols.get(d.Status__c).cartoes.add(k);
            q.documentos++;
            if (d.Status__c == 'Publicada') q.publicados++;
        }
        for (Processo_Critico__c p : procs) {
            if (comDoc.contains(p.Id)) continue;
            q.processosSemDocumento++;
            Cartao k = new Cartao();
            k.processoId = p.Id;
            k.processo = p.Name;
            k.titulo = p.Name;
            k.criticidade = RaizCockpitService.rotulo(Processo_Critico__c.Criticidade__c, p.Criticidade__c);
            k.estadoCobertura = p.Estado_Cobertura__c;
            k.status = BACKLOG;
            k.proximaEtapa = 'Em elaboração';
            k.podeAvancar = true;
            colBacklog.cartoes.add(k);
        }
        for (Coluna c : q.colunas) c.total = c.cartoes.size();
        return q;
    }

    /** CRM_Kanban_Task__c ja tinha lookup para o documento: mostra quantas demandas o citam. */
    private static Map<Id, Integer> contarDemandas(List<Business_Rule__c> docs) {
        Map<Id, Integer> m = new Map<Id, Integer>();
        if (docs.isEmpty()) return m;
        Set<Id> ids = new Map<Id, Business_Rule__c>(docs).keySet();
        try {
            for (AggregateResult ar : [
                SELECT Business_Rule__c br, COUNT(Id) n
                FROM CRM_Kanban_Task__c
                WHERE Business_Rule__c IN :ids
                WITH USER_MODE
                GROUP BY Business_Rule__c
            ]) {
                m.put((Id) ar.get('br'), (Integer) ar.get('n'));
            }
        } catch (Exception e) {
            // Sem acesso ao Kanban: o quadro segue, so sem a contagem.
            System.debug(LoggingLevel.WARN, 'Kanban indisponivel: ' + e.getMessage());
        }
        return m;
    }

    @TestVisible
    private static List<String> pendencias(Business_Rule__c d) {
        List<String> out = new List<String>();
        if (vazio(d.Proposito_Documento__c)) out.add('Propósito');
        if (vazio(d.Descricao_Demanda__c)) out.add('Descrição');
        if (vazio(d.Criterios_Aceite__c)) out.add('Critérios de aceite');
        if (vazio(d.Cenarios_Teste__c)) out.add('Cenários de teste');
        return out;
    }

    private static Boolean vazio(String html) {
        return html == null || String.isBlank(html.stripHtmlTags());
    }

    private static Cartao cartao(Business_Rule__c d, Processo_Critico__c p, Boolean aprovador) {
        Cartao k = new Cartao();
        k.id = d.Id;
        k.processoId = d.Processo_Critico__c;
        k.titulo = d.Title__c;
        k.processo = p == null ? null : p.Name;
        k.criticidade = p == null ? null : RaizCockpitService.rotulo(Processo_Critico__c.Criticidade__c, p.Criticidade__c);
        k.estadoCobertura = p == null ? null : p.Estado_Cobertura__c;
        k.status = d.Status__c;
        k.ultimaRevisao = d.Last_Review_Date__c;
        k.pendencias = pendencias(d);
        k.governanca = d.Governanca_Status__c;
        k.prazoRevisao = d.Prazo_Revisao__c;
        Integer i = FLUXO.indexOf(d.Status__c);
        k.podeVoltar = (i == 1 || i == 2);
        if (i < FLUXO.size() - 1) {
            String prox = FLUXO[i + 1];
            k.proximaEtapa = ROTULO_COLUNA.get(prox);
            if (EXIGE_APROVADOR.contains(prox) && !aprovador) {
                k.motivoBloqueio = 'Exige permissão de aprovação.';
            } else if (EXIGE_APROVADOR.contains(prox) && !k.pendencias.isEmpty()) {
                k.motivoBloqueio = 'Falta: ' + String.join(k.pendencias, ', ') + '.';
            } else {
                k.podeAvancar = true;
            }
        }
        return k;
    }

    // ============================================================ escrita
    private static final Map<String, String> CRITICIDADE_DOC = new Map<String, String>{
        'Critico' => 'Critica',
        'Alto' => 'Alta',
        'Medio' => 'Media',
        'Baixo' => 'Baixa'
    };
    private static final Map<String, String> DOMINIO_DOC = new Map<String, String>{
        'Fiscal' => 'Fiscal',
        'Comercial' => 'Comercial',
        'Logistica' => 'Logistica',
        'TI' => 'Integracao'
    };

    /** Acao explicita: cria o documento (Draft) do processo que esta no Backlog. */
    @AuraEnabled
    public static Id criarDocumento(Id processoId) {
        if (processoId == null) throw aura('Escolha um processo.');
        try {
            List<Processo_Critico__c> ps = [
                SELECT Id, Name, Criticidade__c, Area__c
                FROM Processo_Critico__c
                WHERE Id = :processoId
                WITH USER_MODE
                LIMIT 1
            ];
            if (ps.isEmpty()) throw aura('Processo não encontrado ou sem acesso.');
            Integer existentes = [
                SELECT COUNT()
                FROM Business_Rule__c
                WHERE Processo_Critico__c = :processoId AND Status__c IN :FLUXO
                WITH USER_MODE
            ];
            if (existentes > 0) throw aura('Este processo já tem documento no quadro.');
            List<Project__c> proj = [SELECT Id FROM Project__c WHERE Name = :PROJETO_RAIZ WITH USER_MODE LIMIT 1];
            if (proj.isEmpty()) {
                throw aura('Projeto "' + PROJETO_RAIZ + '" não encontrado. Rode a carga da Onda 5.');
            }
            Processo_Critico__c p = ps[0];
            Business_Rule__c d = new Business_Rule__c(
                Title__c = ('Registro — ' + p.Name).left(255),
                Status__c = 'Draft',
                Criticality__c = CRITICIDADE_DOC.containsKey(p.Criticidade__c) ? CRITICIDADE_DOC.get(p.Criticidade__c) : 'Media',
                Domain__c = DOMINIO_DOC.containsKey(p.Area__c) ? DOMINIO_DOC.get(p.Area__c) : 'Outro',
                Processo_Critico__c = p.Id,
                Project__c = proj[0].Id
            );
            Database.insert(d, AccessLevel.USER_MODE);
            return d.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    /** Uma etapa por vez: direcao 1 avanca, -1 volta. */
    @AuraEnabled
    public static void moverDocumento(Id documentoId, Integer direcao) {
        if (documentoId == null || (direcao != 1 && direcao != -1)) throw aura('Movimento inválido.');
        try {
            List<Business_Rule__c> ds = [
                SELECT Id, Status__c, Processo_Critico__c, Proposito_Documento__c, Descricao_Demanda__c,
                    Criterios_Aceite__c, Cenarios_Teste__c
                FROM Business_Rule__c
                WHERE Id = :documentoId
                WITH USER_MODE
                LIMIT 1
            ];
            if (ds.isEmpty()) throw aura('Documento não encontrado ou sem acesso.');
            Business_Rule__c d = ds[0];
            Integer i = FLUXO.indexOf(d.Status__c);
            Integer j = i + direcao;
            if (i < 0 || j < 0 || j >= FLUXO.size() || (direcao == -1 && i == FLUXO.size() - 1)) {
                throw aura('Não é possível mover a partir de ' + d.Status__c + '.');
            }
            String destino = FLUXO[j];
            if (direcao == 1 && EXIGE_APROVADOR.contains(destino) && !podeAprovar()) {
                throw aura('Aprovar e publicar exigem a permissão "RAIZ - Aprovar documentos".');
            }
            // Conteudo minimo cobrado aqui tambem: nao depende da regra de validacao
            // da org estar ativa (o deploy mostrou que, nesta org, ela nao barrou).
            if (direcao == 1 && EXIGE_APROVADOR.contains(destino)) {
                List<String> falta = pendencias(d);
                if (!falta.isEmpty()) {
                    throw aura('Preencha antes de aprovar: ' + String.join(falta, ', ') + '.');
                }
            }
            Business_Rule__c upd = new Business_Rule__c(Id = d.Id, Status__c = destino);
            if (destino == 'Publicada') upd.Last_Review_Date__c = Date.today();
            Database.update(upd, AccessLevel.USER_MODE);

            if (destino == 'Publicada' && d.Processo_Critico__c != null) {
                Database.update(
                    new Processo_Critico__c(
                        Id = d.Processo_Critico__c,
                        Status_Registro__c = 'Registrado',
                        Ultima_Revisao__c = Date.today()
                    ),
                    AccessLevel.USER_MODE
                );
            }
            // Onda 7: cartao do Kanban acompanha o status e a tarefa de revisao e
            // encerrada quando o documento sai de revisao. Nunca lanca.
            RaizGovernancaAction.aoMudarStatus(d.Id, destino);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    // ============================================================ erros
    private static AuraHandledException aura(String m) {
        AuraHandledException e = new AuraHandledException(m);
        e.setMessage(m);
        return e;
    }

    private static AuraHandledException erroAmigavel(Exception e) {
        String m = e.getMessage();
        if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
            m = ((DmlException) e).getDmlMessage(0);
        }
        Boolean semAcesso =
            m != null &&
            !m.containsIgnoreCase('cross-reference') &&
            (m.containsIgnoreCase('access') ||
            m.containsIgnoreCase('acesso') ||
            m.containsIgnoreCase('No such column') ||
            m.containsIgnoreCase('not supported') ||
            m.containsIgnoreCase('permission'));
        return aura(semAcesso ? 'SEM_PERMISSAO: seu usuário não tem acesso ao Knowledge Hub. Peça o permission set EBL_RAIZ_Cockpit.' : m);
    }
}
