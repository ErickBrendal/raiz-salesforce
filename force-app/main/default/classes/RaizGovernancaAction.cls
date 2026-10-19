/**
 * RaizGovernancaAction — RAIZ Document Governance Automation (Onda 7).
 * ---------------------------------------------------------------------------
 * Chamada pelo Flow RAIZ_Governanca_Revisao (disparado quando o documento
 * PASSA a "Em Analise"). O Flow so roteia; as regras estao aqui e em
 * RaizGovernancaService (ADR-012).
 *
 *   submeter  valida (RaizGovernancaService.avaliarSubmissao)
 *             ok      -> Task para o revisor, cartao do Kanban, notificacao,
 *                        situacao "Em revisao com X ate dd/mm", log Sucesso
 *             faltas  -> nada de Task nem cartao; situacao "Bloqueado: falta ...",
 *                        aviso ao autor, log Bloqueado
 *   escalar   caminho agendado (1 dia apos Prazo_Revisao__c): se ainda em
 *             revisao e nao escalado, avisa revisor e autor UMA vez
 *   aoMudarStatus  chamado pelo Knowledge Hub ao mover o documento: move o
 *             cartao e encerra a Task de revisao quando o documento sai de revisao
 *
 * IDEMPOTENCIA: Task so e criada se nao houver Task de revisao aberta; log com
 * chave (RaizLog); escalonamento marcado em Escalonado_Em__c.
 *
 * SEGURANCA: without sharing, de proposito (ADR-018). A automacao cria a Task
 * de OUTRA pessoa (o revisor) e grava campos que so ela escreve
 * (Governanca_Status__c, Data_Solicitacao_Revisao__c, Escalonado_Em__c).
 * Ela nunca altera Status__c, dono, nem conteudo do documento. O cartao do
 * Kanban continua no modo do usuario (RaizGovernancaService.sincronizarCartao).
 * NUNCA lanca excecao para o Flow: um erro aqui nao pode desfazer a mudanca de
 * status feita pelo usuario. Erros viram log.
 */
public without sharing class RaizGovernancaAction {
    public static final String NOTIFICACAO = 'RAIZ_Revisao_Documento';
    public static final String PREFIXO_TAREFA = 'RAIZ · Revisar: ';
    public static final Integer LIMITE_LOTE = 20;
    private static final String PADRAO_TAREFA = PREFIXO_TAREFA + '%';
    private static final String TIPO = 'Automacao';

    public class Requisicao {
        @InvocableVariable(required=true label='Documento (Id)')
        public Id documentoId;
        @InvocableVariable(required=true label='Ação: submeter ou escalar')
        public String acao;
    }

    @InvocableMethod(
        label='RAIZ - Governança documental'
        description='Submete o documento à revisão (Task, Kanban, notificação, log) ou escala a revisão vencida.'
        category='RAIZ'
    )
    public static void executar(List<Requisicao> reqs) {
        Integer n = 0;
        for (Requisicao r : reqs) {
            n++;
            String acao = r.acao == null ? 'submeter' : r.acao.toLowerCase();
            if (n > LIMITE_LOTE) {
                RaizLog.registrar(TIPO, acao, 'Erro', r.documentoId, 'LOTE:' + r.documentoId + ':' + n + ':' + DateTime.now().getTime(),
                    'Lote acima de ' + LIMITE_LOTE + ' documentos na mesma transação: este não foi processado. Reenvie em lotes menores.');
                continue;
            }
            try {
                if (acao == 'escalar') {
                    escalar(r.documentoId);
                } else {
                    submeter(r.documentoId);
                }
            } catch (Exception e) {
                RaizLog.registrar(TIPO, acao, 'Erro', r.documentoId, 'ERRO:' + acao + ':' + r.documentoId + ':' + n + ':' + DateTime.now().getTime(),
                    e.getTypeName() + ': ' + e.getMessage());
            }
        }
    }

    // ========================================================= submeter
    public static void submeter(Id docId) {
        Business_Rule__c d = carregar(docId);
        if (d == null) {
            RaizLog.registrar(TIPO, 'submissao', 'Erro', docId, 'NAO-ENCONTRADO:' + docId, 'Documento não encontrado.');
            return;
        }
        if (d.Status__c != 'Em Analise') {
            RaizLog.registrar(TIPO, 'submissao', 'Ignorado', d.Id, 'SUBMISSAO-IGNORADA:' + d.Id + ':' + d.Status__c,
                'Documento em "' + d.Status__c + '": só "Em Analise" é submetido.');
            return;
        }
        RaizGovernancaService.Avaliacao a = RaizGovernancaService.avaliarSubmissao(d);
        if (!a.apto) {
            String sit = ('Bloqueado: falta ' + String.join(a.faltas, ', ')).left(255);
            update new Business_Rule__c(Id = d.Id, Governanca_Status__c = sit);
            String msg = sit + '. Nenhuma tarefa criada e o cartão do Kanban não foi movido.';
            Boolean novo = RaizLog.registrar(TIPO, 'submissao', 'Bloqueado', d.Id, 'BLOQUEIO:' + d.Id + ':' + String.join(a.faltas, '|'), msg);
            if (novo) {
                notificar(new Set<Id>{ d.OwnerId }, 'Encaminhamento bloqueado', d.Title__c + ': ' + sit + '.', d.Id);
            }
            return;
        }

        List<Task> abertas = [
            SELECT Id
            FROM Task
            WHERE WhatId = :d.Id AND IsClosed = FALSE AND Subject LIKE :PADRAO_TAREFA
            LIMIT 1
        ];
        Boolean novaTarefa = abertas.isEmpty();
        Id tarefaId;
        if (novaTarefa) {
            Task t = new Task(
                OwnerId = d.Revisor__c,
                WhatId = d.Id,
                Subject = (PREFIXO_TAREFA + d.Title__c).left(255),
                ActivityDate = d.Prazo_Revisao__c,
                Priority = d.Criticality__c == 'Critica' ? 'High' : 'Normal',
                Status = 'Not Started',
                Description = 'Revisão pedida pela governança documental do RAIZ. Avalie no Knowledge Hub (coluna "Em revisão"); aprovar exige que resultado esperado e exceções estejam preenchidos.'
            );
            insert t;
            tarefaId = t.Id;
        } else {
            tarefaId = abertas[0].Id;
        }

        String nomeRevisor = [SELECT Name FROM User WHERE Id = :d.Revisor__c LIMIT 1].Name;
        String prazo = d.Prazo_Revisao__c == null ? ' (sem prazo)' : ' até ' + d.Prazo_Revisao__c.format();
        Business_Rule__c upd = new Business_Rule__c(Id = d.Id, Governanca_Status__c = ('Em revisão com ' + nomeRevisor + prazo).left(255));
        if (novaTarefa) {
            upd.Data_Solicitacao_Revisao__c = DateTime.now();
            upd.Escalonado_Em__c = null;
        }
        update upd;

        RaizGovernancaService.Cartao c = RaizGovernancaService.sincronizarCartao(d.Id);
        List<String> partes = new List<String>{
            (novaTarefa ? 'Tarefa de revisão criada para ' : 'Tarefa de revisão já existia para ') + nomeRevisor + prazo + '.',
            c.aviso != null ? c.aviso : 'Cartão do Kanban ' + c.acao + ' em "' + c.etapa + '".'
        };
        if (novaTarefa) {
            Boolean ok = notificar(
                new Set<Id>{ d.Revisor__c },
                'Revisão pedida',
                d.Title__c + prazo + '. Abra o Knowledge Hub, coluna "Em revisão".',
                d.Id
            );
            partes.add(ok ? 'Revisor notificado.' : 'Notificação não enviada (tipo ausente ou falha); a tarefa continua criada.');
        } else {
            partes.add('Sem nova notificação (idempotência).');
        }
        partes.addAll(a.avisos);
        RaizLog.registrar(TIPO, 'submissao', 'Sucesso', d.Id, 'SUBMISSAO:' + d.Id + ':' + tarefaId, String.join(partes, ' '));
    }

    // ========================================================== escalar
    public static void escalar(Id docId) {
        Business_Rule__c d = carregar(docId);
        if (d == null) {
            RaizLog.registrar(TIPO, 'escalonamento', 'Erro', docId, 'NAO-ENCONTRADO:' + docId, 'Documento não encontrado.');
            return;
        }
        if (d.Status__c != 'Em Analise') {
            RaizLog.registrar(TIPO, 'escalonamento', 'Ignorado', d.Id, 'ESCALONAMENTO-IGNORADO:' + d.Id + ':' + d.Status__c,
                'O documento já saiu de revisão ("' + d.Status__c + '"): nada a escalar.');
            return;
        }
        if (d.Prazo_Revisao__c == null || d.Prazo_Revisao__c >= Date.today()) {
            RaizLog.registrar(TIPO, 'escalonamento', 'Ignorado', d.Id, 'ESCALONAMENTO-NO-PRAZO:' + d.Id + ':' + d.Prazo_Revisao__c,
                'Prazo não vencido ou não informado: nada a escalar.');
            return;
        }
        String chave = 'ESCALONAMENTO:' + d.Id + ':' + String.valueOf(d.Prazo_Revisao__c);
        if (d.Escalonado_Em__c != null) {
            RaizLog.registrar(TIPO, 'escalonamento', 'Ignorado', d.Id, chave + ':REPETIDO', 'Já escalado em ' + d.Escalonado_Em__c.format() + ': sem novo aviso.');
            return;
        }
        String sit = ('Revisão atrasada: prazo ' + d.Prazo_Revisao__c.format() + ' vencido').left(255);
        update new Business_Rule__c(Id = d.Id, Escalonado_Em__c = DateTime.now(), Governanca_Status__c = sit);
        List<Task> abertas = [
            SELECT Id
            FROM Task
            WHERE WhatId = :d.Id AND IsClosed = FALSE AND Subject LIKE :PADRAO_TAREFA
        ];
        for (Task t : abertas) t.Priority = 'High';
        update abertas;
        Set<Id> quem = new Set<Id>{ d.OwnerId };
        if (d.Revisor__c != null) quem.add(d.Revisor__c);
        Boolean ok = notificar(quem, 'Revisão atrasada', d.Title__c + ': ' + sit + '.', d.Id);
        RaizLog.registrar(TIPO, 'escalonamento', 'Sucesso', d.Id, chave,
            sit + '. Tarefas abertas com prioridade alta: ' + abertas.size() + '. ' + (ok ? 'Revisor e autor notificados.' : 'Notificação não enviada.'));
    }

    // ===================================================== mudanca de status
    /** Chamado pelo Knowledge Hub depois de mover o documento. Nunca lanca. */
    public static void aoMudarStatus(Id docId, String novoStatus) {
        try {
            RaizGovernancaService.Cartao c = RaizGovernancaService.sincronizarCartao(docId);
            if (novoStatus == 'Em Analise') return; // o Flow cuida da submissao
            List<Task> abertas = [
                SELECT Id
                FROM Task
                WHERE WhatId = :docId AND IsClosed = FALSE AND Subject LIKE :PADRAO_TAREFA
            ];
            for (Task t : abertas) t.Status = 'Completed';
            update abertas;
            String hoje = Date.today().format();
            String sit = novoStatus == 'Aprovada'
                ? 'Aprovado em ' + hoje
                : novoStatus == 'Publicada' ? 'Publicado em ' + hoje : 'Devolvido para elaboração em ' + hoje;
            update new Business_Rule__c(Id = docId, Governanca_Status__c = sit);
            RaizLog.registrar(TIPO, 'mudanca de status', 'Sucesso', docId, 'STATUS:' + docId + ':' + novoStatus + ':' + String.valueOf(Date.today()),
                sit + '. Tarefas de revisão encerradas: ' + abertas.size() + '. ' + (c.aviso != null ? c.aviso : 'Cartão do Kanban ' + c.acao + ' em "' + c.etapa + '".'));
        } catch (Exception e) {
            RaizLog.registrar(TIPO, 'mudanca de status', 'Erro', docId, 'ERRO:status:' + docId + ':' + DateTime.now().getTime(), e.getTypeName() + ': ' + e.getMessage());
        }
    }

    // ============================================================ apoio
    private static Business_Rule__c carregar(Id docId) {
        if (docId == null) return null;
        List<Business_Rule__c> ds = [
            SELECT Id, Title__c, Status__c, OwnerId, Revisor__c, Prazo_Revisao__c, Escalonado_Em__c, Criticality__c,
                Processo_Critico__c, Proposito_Documento__c, Descricao_Demanda__c, Criterios_Aceite__c, Cenarios_Teste__c
            FROM Business_Rule__c
            WHERE Id = :docId
            LIMIT 1
        ];
        return ds.isEmpty() ? null : ds[0];
    }

    private static Id tipoNotificacao;
    @TestVisible
    private static Boolean notificar(Set<Id> usuarios, String titulo, String corpo, Id alvo) {
        try {
            if (tipoNotificacao == null) {
                List<CustomNotificationType> ts = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICACAO LIMIT 1];
                if (ts.isEmpty()) return false;
                tipoNotificacao = ts[0].Id;
            }
            Set<String> ids = new Set<String>();
            for (Id u : usuarios) {
                if (u != null) ids.add(u);
            }
            if (ids.isEmpty()) return false;
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(tipoNotificacao);
            n.setTitle(('RAIZ · ' + titulo).left(250));
            n.setBody(corpo == null ? '' : corpo.left(750));
            n.setTargetId(alvo);
            n.send(ids);
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'RAIZ notificacao falhou: ' + e.getMessage());
            return false;
        }
    }
}
