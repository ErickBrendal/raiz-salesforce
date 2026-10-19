/**
 * RaizGovernancaService — regras de governanca documental do RAIZ 4.0.
 * ---------------------------------------------------------------------------
 * Ponto unico para tres perguntas que o cadastro guiado (Onda 6) e a
 * automacao de revisao (Onda 7) fazem:
 *
 *   1. Quem pode revisar?      revisoresElegiveis(autorId)
 *      Usuarios ativos com a permissao RAIZ_Aprovar_Documentos, exceto o autor
 *      ("quem escreve nao aprova").
 *   2. O documento pode ser encaminhado?   avaliarSubmissao(doc)
 *      Devolve FALTAS (o que impede o encaminhamento pela governanca) e AVISOS
 *      (o que nao impede agora, mas sera cobrado depois). Decisao D6: o Hub nao
 *      bloqueia Draft -> Em Analise; quem usa estas faltas e a automacao.
 *   3. Como o Kanban acompanha o documento?   sincronizarCartao(docId)
 *      Um cartao por documento (prefixo "RAIZ · "), criado ou movido pelo
 *      servico do proprio Kanban. Falha no Kanban NUNCA desfaz o documento:
 *      vira aviso para o usuario.
 *
 * SEGURANCA: with sharing; leituras de negocio WITH USER_MODE. A consulta de
 * quem tem a permissao (SetupEntityAccess / PermissionSetAssignment) roda no
 * modo de sistema porque usuarios comuns nao leem metadados de seguranca; ela
 * devolve apenas Id e nome de usuarios ativos.
 */
public with sharing class RaizGovernancaService {
    public static final String PREFIXO_CARTAO = 'RAIZ · ';

    /** Status do documento -> coluna do Kanban existente (valores reais da org, auditoria 18/10/2026). */
    public static final Map<String, String> ETAPA_KANBAN = new Map<String, String>{
        'Draft' => 'Backlog',
        'Em Analise' => 'Em atendimento-Analise TI',
        'Aprovada' => 'Pendente-Aguardando Publicação',
        'Publicada' => 'Fechado'
    };

    // ================================================================ DTOs
    public class Revisor {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String nome;
    }

    public class Avaliacao {
        @AuraEnabled
        public List<String> faltas = new List<String>();
        @AuraEnabled
        public List<String> avisos = new List<String>();
        @AuraEnabled
        public Boolean apto {
            get {
                return faltas.isEmpty();
            }
        }
    }

    public class Cartao {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String etapa;
        /** criado | movido | sem mudança | não atualizado */
        @AuraEnabled
        public String acao;
        @AuraEnabled
        public String aviso;
    }

    // ======================================================= revisores
    public static List<Revisor> revisoresElegiveis(Id autorId) {
        List<Revisor> out = new List<Revisor>();
        List<CustomPermission> cps = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :RaizKnowledgeService.PERMISSAO_APROVAR
            LIMIT 1
        ];
        if (cps.isEmpty()) return out;
        Set<Id> conjuntos = new Set<Id>();
        for (SetupEntityAccess sea : [SELECT ParentId FROM SetupEntityAccess WHERE SetupEntityId = :cps[0].Id]) {
            conjuntos.add(sea.ParentId);
        }
        if (conjuntos.isEmpty()) return out;
        Set<Id> vistos = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :conjuntos AND Assignee.IsActive = TRUE
            ORDER BY Assignee.Name
            LIMIT 500
        ]) {
            if (psa.AssigneeId == autorId || vistos.contains(psa.AssigneeId)) continue;
            vistos.add(psa.AssigneeId);
            Revisor r = new Revisor();
            r.id = psa.AssigneeId;
            r.nome = psa.Assignee.Name;
            out.add(r);
        }
        return out;
    }

    public static Boolean revisorElegivel(Id revisorId, Id autorId) {
        if (revisorId == null || revisorId == autorId) return false;
        for (Revisor r : revisoresElegiveis(autorId)) {
            if (r.id == revisorId) return true;
        }
        return false;
    }

    // ======================================================= submissao
    /**
     * Campos usados: Title__c, Proposito_Documento__c, Descricao_Demanda__c,
     * Criterios_Aceite__c, Cenarios_Teste__c, Revisor__c, Prazo_Revisao__c,
     * Processo_Critico__c e o autor (OwnerId; se nulo, o usuario atual).
     */
    public static Avaliacao avaliarSubmissao(Business_Rule__c d) {
        Avaliacao a = new Avaliacao();
        Id autor = d.OwnerId != null ? d.OwnerId : UserInfo.getUserId();
        if (d.Processo_Critico__c == null) a.faltas.add('Processo crítico');
        if (String.isBlank(d.Title__c)) a.faltas.add('Título');
        if (vazio(d.Proposito_Documento__c)) a.faltas.add('Resumo e finalidade');
        if (vazio(d.Descricao_Demanda__c)) a.faltas.add('Etapas operacionais');
        if (d.Revisor__c == null) {
            a.faltas.add('Revisor');
        } else if (d.Revisor__c == autor) {
            a.faltas.add('Revisor diferente do autor');
        } else if (!revisorElegivel(d.Revisor__c, autor)) {
            a.faltas.add('Revisor com permissão de aprovação');
        }
        if (d.Prazo_Revisao__c == null) {
            a.avisos.add('Sem prazo de revisão: o documento não terá acompanhamento de vencimento.');
        }
        List<String> paraAprovar = new List<String>();
        if (vazio(d.Criterios_Aceite__c)) paraAprovar.add('Resultado esperado');
        if (vazio(d.Cenarios_Teste__c)) paraAprovar.add('Exceções');
        if (!paraAprovar.isEmpty()) {
            a.avisos.add('Necessário para aprovar: ' + String.join(paraAprovar, ', ') + '.');
        }
        return a;
    }

    public static Boolean vazio(String html) {
        return html == null || String.isBlank(html.stripHtmlTags());
    }

    // ========================================================== kanban
    public static Cartao sincronizarCartao(Id documentoId) {
        Cartao c = new Cartao();
        try {
            List<Business_Rule__c> ds = [
                SELECT Id, Title__c, Status__c, Project__c, Governanca_Status__c, Processo_Critico__r.Name
                FROM Business_Rule__c
                WHERE Id = :documentoId
                WITH USER_MODE
                LIMIT 1
            ];
            if (ds.isEmpty()) {
                return naoAtualizado(c, 'documento não encontrado ou sem acesso.');
            }
            Business_Rule__c d = ds[0];
            String etapa = ETAPA_KANBAN.get(d.Status__c);
            // Onda 8: encaminhamento barrado pela governanca nao avanca o cartao (fica no Backlog).
            if (d.Status__c == 'Em Analise' && d.Governanca_Status__c != null && d.Governanca_Status__c.startsWith('Bloqueado')) {
                etapa = 'Backlog';
            }
            if (etapa == null) {
                return naoAtualizado(c, 'status ' + d.Status__c + ' não tem coluna no Kanban.');
            }
            String prefixo = PREFIXO_CARTAO + '%';
            List<CRM_Kanban_Task__c> existentes = [
                SELECT Id, CRM_Kanban_Stage__c
                FROM CRM_Kanban_Task__c
                WHERE Business_Rule__c = :d.Id AND Name LIKE :prefixo
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 1
            ];
            c.etapa = etapa;
            if (existentes.isEmpty()) {
                String processo = d.Processo_Critico__r == null ? '' : d.Processo_Critico__r.Name;
                CRM_Kanban_Task__c novo = new CRM_Kanban_Task__c(
                    Name = (PREFIXO_CARTAO + d.Title__c).left(80),
                    CRM_Kanban_Stage__c = etapa,
                    CRM_Project__c = d.Project__c,
                    Business_Rule__c = d.Id,
                    CRM_Category__c = 'Outro',
                    CRM_Type__c = 'Interno',
                    Description__c = 'Acompanhamento do documento RAIZ do processo "' + processo +
                        '". Cartão mantido pelo RAIZ: muda de coluna quando o documento muda de status.'
                );
                c.id = CRMKanbanService.createTask(novo).Id;
                c.acao = 'criado';
            } else if (existentes[0].CRM_Kanban_Stage__c != etapa) {
                c.id = existentes[0].Id;
                CRMKanbanService.moveTaskToStage(c.id, etapa);
                c.acao = 'movido';
            } else {
                c.id = existentes[0].Id;
                c.acao = 'sem mudança';
            }
        } catch (Exception e) {
            return naoAtualizado(c, e.getMessage());
        }
        return c;
    }

    private static Cartao naoAtualizado(Cartao c, String motivo) {
        c.acao = 'não atualizado';
        c.aviso = 'O documento foi salvo, mas o cartão do Kanban não foi atualizado: ' + motivo;
        return c;
    }
}
