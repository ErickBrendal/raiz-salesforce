/**
 * RaizMitigationService — planos e acoes de mitigacao (Onda 3).
 * ---------------------------------------------------------------------------
 * Fecha o ciclo do metodo: o motor de risco diz ONDE esta o risco, o
 * simulador diz O QUE para, e o plano diz O QUE FAZER, com dono e prazo.
 *
 * REGRAS
 *   - Sugestao: processo que nao esta "Coberto", ou cujo registro nao esta
 *     atualizado, e que nao tem plano aberto (Rascunho ou Em execucao).
 *   - Objetivo sugerido pelo estado do processo (ver objetivoPara()).
 *   - Criar plano e uma ACAO EXPLICITA do usuario (nunca automatica).
 *   - Um processo tem no maximo um plano aberto.
 *   - Concluir o plano exige todas as acoes concluidas (regra de validacao).
 *   - Concluir o plano NAO cria habilitacao Apto: a cobertura so muda quando
 *     a habilitacao for registrada com evidencia. Plano e intencao; habilitacao
 *     e fato.
 *
 * SEGURANCA: with sharing; leituras WITH USER_MODE; escritas AccessLevel.USER_MODE.
 */
public with sharing class RaizMitigationService {
    public static final String HABILITAR = 'Habilitar substituto';
    public static final String REGISTRAR = 'Registrar o processo';
    public static final String ATUALIZAR = 'Atualizar o registro';
    public static final String LEVANTAR = 'Levantar informacao';

    public static final String RASCUNHO = 'Rascunho';
    public static final String EM_EXECUCAO = 'Em execucao';
    public static final String CONCLUIDO = 'Concluido';
    public static final String CANCELADO = 'Cancelado';
    public static final String ACAO_CONCLUIDA = 'Concluida';
    public static final Set<String> ABERTOS = new Set<String>{ RASCUNHO, EM_EXECUCAO };

    /** Prazo padrao de um plano novo, em dias. Premissa exibida na tela. */
    public static final Integer PRAZO_PADRAO_DIAS = 30;

    private static final Map<String, String> ROTULO_OBJETIVO = new Map<String, String>{
        HABILITAR => 'Habilitar substituto',
        REGISTRAR => 'Registrar o processo',
        ATUALIZAR => 'Atualizar o registro',
        LEVANTAR => 'Levantar informação',
        'Aplicar no sistema' => 'Aplicar no sistema'
    };
    private static final Map<String, String> ROTULO_STATUS = new Map<String, String>{
        RASCUNHO => 'Rascunho',
        EM_EXECUCAO => 'Em execução',
        CONCLUIDO => 'Concluído',
        CANCELADO => 'Cancelado',
        'A fazer' => 'A fazer',
        'Em andamento' => 'Em andamento',
        ACAO_CONCLUIDA => 'Concluída',
        'Bloqueada' => 'Bloqueada'
    };

    // ================================================================ DTOs
    public class Sugestao {
        @AuraEnabled
        public Id processoId;
        @AuraEnabled
        public String processo;
        @AuraEnabled
        public String conta;
        @AuraEnabled
        public String estado;
        @AuraEnabled
        public Integer score;
        @AuraEnabled
        public String farol;
        @AuraEnabled
        public Decimal exposicao;
        @AuraEnabled
        public String objetivo;
        @AuraEnabled
        public String objetivoRotulo;
        @AuraEnabled
        public String motivo;
    }

    public class AcaoDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String descricao;
        @AuraEnabled
        public String tipo;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String statusRotulo;
        @AuraEnabled
        public Boolean concluida;
        @AuraEnabled
        public Boolean atrasada;
        @AuraEnabled
        public Date prazo;
        @AuraEnabled
        public String responsavel;
    }

    public class PlanoDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String nome;
        @AuraEnabled
        public Id processoId;
        @AuraEnabled
        public String processo;
        @AuraEnabled
        public String objetivoRotulo;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String statusRotulo;
        @AuraEnabled
        public Boolean atrasado;
        @AuraEnabled
        public Date dataAlvo;
        @AuraEnabled
        public String responsavel;
        @AuraEnabled
        public Integer acoesTotal;
        @AuraEnabled
        public Integer acoesConcluidas;
        @AuraEnabled
        public Integer progresso; // 0-100
        @AuraEnabled
        public Integer scoreInicial;
        @AuraEnabled
        public Integer scoreAtual;
        @AuraEnabled
        public String estadoInicial;
        @AuraEnabled
        public String estadoAtual;
        @AuraEnabled
        public Boolean podeConcluir;
        @AuraEnabled
        public List<AcaoDTO> acoes = new List<AcaoDTO>();
    }

    public class Painel {
        @AuraEnabled
        public Integer planosAbertos = 0;
        @AuraEnabled
        public Integer planosAtrasados = 0;
        @AuraEnabled
        public Integer acoesTotal = 0;
        @AuraEnabled
        public Integer acoesConcluidas = 0;
        @AuraEnabled
        public Integer processosSemPlano = 0;
        @AuraEnabled
        public List<Sugestao> sugestoes = new List<Sugestao>();
        @AuraEnabled
        public List<PlanoDTO> planos = new List<PlanoDTO>();
        @AuraEnabled
        public List<String> premissas = new List<String>();
    }

    // ============================================================ leitura
    @AuraEnabled(cacheable=true)
    public static Painel getPainel(Id contaId) {
        try {
            return montarPainel(contaId);
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    private static Painel montarPainel(Id contaId) {
        Painel pn = new Painel();
        pn.premissas.add('Sugestão = processo que não está Coberto ou com registro não atualizado, sem plano aberto.');
        pn.premissas.add('Plano novo nasce com prazo de ' + PRAZO_PADRAO_DIAS + ' dias e ações padrão do objetivo; ajuste no registro.');
        pn.premissas.add('Concluir o plano não marca ninguém como apto: a cobertura só muda com habilitação registrada.');

        List<Processo_Critico__c> procs = (contaId == null) ? processosTodos() : processosDaConta(contaId);
        Map<Id, Processo_Critico__c> porId = new Map<Id, Processo_Critico__c>(procs);

        List<Plano_Mitigacao__c> planos = [
            SELECT
                Id,
                Name,
                Processo__c,
                Processo__r.Name,
                Objetivo__c,
                Status__c,
                Atrasado__c,
                Data_Alvo__c,
                Responsavel__r.Name,
                Acoes_Total__c,
                Acoes_Concluidas__c,
                Score_Inicial__c,
                Estado_Inicial__c,
                (
                    SELECT Id, Name, Tipo__c, Status__c, Atrasada__c, Prazo__c, Responsavel__r.Name
                    FROM Acoes__r
                    ORDER BY Ordem__c NULLS LAST, Name
                )
            FROM Plano_Mitigacao__c
            WHERE Processo__c IN :porId.keySet() AND Status__c IN :ABERTOS
            WITH USER_MODE
            ORDER BY Data_Alvo__c NULLS LAST
            LIMIT 200
        ];

        Set<Id> comPlano = new Set<Id>();
        for (Plano_Mitigacao__c p : planos) {
            comPlano.add(p.Processo__c);
            PlanoDTO d = dto(p, porId.get(p.Processo__c));
            pn.planos.add(d);
            pn.planosAbertos++;
            if (d.atrasado) {
                pn.planosAtrasados++;
            }
            pn.acoesTotal += d.acoesTotal;
            pn.acoesConcluidas += d.acoesConcluidas;
        }

        for (Processo_Critico__c p : procs) {
            String obj = objetivoPara(p);
            if (obj == null || comPlano.contains(p.Id)) {
                continue;
            }
            pn.processosSemPlano++;
            if (pn.sugestoes.size() < 10) {
                pn.sugestoes.add(sugestao(p, obj));
            }
        }
        return pn;
    }

    private static List<Processo_Critico__c> processosTodos() {
        return [
            SELECT
                Id,
                Name,
                Conta__r.Name,
                Estado_Cobertura__c,
                Atualizado__c,
                Status_Registro__c,
                Risco_Score__c,
                Farol__c,
                Exposicao_Financeira__c
            FROM Processo_Critico__c
            WITH USER_MODE
            ORDER BY Risco_Score__c DESC NULLS LAST, Exposicao_Financeira__c DESC NULLS LAST
            LIMIT 2000
        ];
    }

    private static List<Processo_Critico__c> processosDaConta(Id contaId) {
        return [
            SELECT
                Id,
                Name,
                Conta__r.Name,
                Estado_Cobertura__c,
                Atualizado__c,
                Status_Registro__c,
                Risco_Score__c,
                Farol__c,
                Exposicao_Financeira__c
            FROM Processo_Critico__c
            WHERE Conta__c = :contaId
            WITH USER_MODE
            ORDER BY Risco_Score__c DESC NULLS LAST, Exposicao_Financeira__c DESC NULLS LAST
            LIMIT 2000
        ];
    }

    /** Objetivo sugerido; null = processo nao precisa de plano. */
    @TestVisible
    private static String objetivoPara(Processo_Critico__c p) {
        String estado = p.Estado_Cobertura__c;
        if (estado == RaizRiskEngine.INSUFICIENTE || String.isBlank(estado)) {
            return LEVANTAR;
        }
        if (estado == RaizRiskEngine.SEM_COBERTURA || estado == RaizRiskEngine.PONTO_UNICO) {
            return HABILITAR;
        }
        if (p.Atualizado__c != true) {
            return (p.Status_Registro__c == 'Registrado' || p.Status_Registro__c == 'Desatualizado')
                ? ATUALIZAR
                : REGISTRAR;
        }
        return null;
    }

    private static Sugestao sugestao(Processo_Critico__c p, String obj) {
        Sugestao s = new Sugestao();
        s.processoId = p.Id;
        s.processo = p.Name;
        s.conta = p.Conta__r == null ? null : p.Conta__r.Name;
        s.estado = p.Estado_Cobertura__c;
        s.score = p.Risco_Score__c == null ? null : p.Risco_Score__c.intValue();
        s.farol = p.Farol__c;
        s.exposicao = p.Exposicao_Financeira__c == null ? 0 : p.Exposicao_Financeira__c;
        s.objetivo = obj;
        s.objetivoRotulo = ROTULO_OBJETIVO.get(obj);
        if (obj == HABILITAR) {
            s.motivo = (p.Estado_Cobertura__c == RaizRiskEngine.SEM_COBERTURA)
                ? 'Ninguém apto hoje.'
                : 'Só uma pessoa apta: se ela faltar, o processo para.';
        } else if (obj == LEVANTAR) {
            s.motivo = 'Não se sabe quem executa: sem habilitação nem número declarado.';
        } else if (obj == ATUALIZAR) {
            s.motivo = 'Registro existe, mas está fora da validade.';
        } else {
            s.motivo = 'Coberto por pessoas, mas sem registro do processo.';
        }
        return s;
    }

    private static PlanoDTO dto(Plano_Mitigacao__c p, Processo_Critico__c proc) {
        PlanoDTO d = new PlanoDTO();
        d.id = p.Id;
        d.nome = p.Name;
        d.processoId = p.Processo__c;
        d.processo = p.Processo__r.Name;
        d.objetivoRotulo = ROTULO_OBJETIVO.containsKey(p.Objetivo__c) ? ROTULO_OBJETIVO.get(p.Objetivo__c) : p.Objetivo__c;
        d.status = p.Status__c;
        d.statusRotulo = ROTULO_STATUS.get(p.Status__c);
        d.atrasado = (p.Atrasado__c == true);
        d.dataAlvo = p.Data_Alvo__c;
        d.responsavel = p.Responsavel__r == null ? 'Sem responsável' : p.Responsavel__r.Name;
        d.acoesTotal = p.Acoes_Total__c == null ? 0 : p.Acoes_Total__c.intValue();
        d.acoesConcluidas = p.Acoes_Concluidas__c == null ? 0 : p.Acoes_Concluidas__c.intValue();
        d.progresso = d.acoesTotal == 0 ? 0 : (Integer) Math.floor(100.0 * d.acoesConcluidas / d.acoesTotal);
        d.scoreInicial = p.Score_Inicial__c == null ? null : p.Score_Inicial__c.intValue();
        d.estadoInicial = p.Estado_Inicial__c;
        if (proc != null) {
            d.scoreAtual = proc.Risco_Score__c == null ? null : proc.Risco_Score__c.intValue();
            d.estadoAtual = proc.Estado_Cobertura__c;
        }
        d.podeConcluir = d.acoesConcluidas == d.acoesTotal;
        for (Acao_Mitigacao__c a : p.Acoes__r) {
            AcaoDTO x = new AcaoDTO();
            x.id = a.Id;
            x.descricao = a.Name;
            x.tipo = a.Tipo__c;
            x.status = a.Status__c;
            x.statusRotulo = ROTULO_STATUS.get(a.Status__c);
            x.concluida = (a.Status__c == ACAO_CONCLUIDA);
            x.atrasada = (a.Atrasada__c == true);
            x.prazo = a.Prazo__c;
            x.responsavel = a.Responsavel__r == null ? null : a.Responsavel__r.Name;
            d.acoes.add(x);
        }
        return d;
    }

    // ============================================================ escrita
    /** Acao explicita do usuario: cria o plano sugerido para o processo. */
    @AuraEnabled
    public static Id criarPlano(Id processoId) {
        if (processoId == null) {
            throw aura('Escolha um processo.');
        }
        try {
            List<Processo_Critico__c> ps = [
                SELECT Id, Name, Estado_Cobertura__c, Atualizado__c, Status_Registro__c, Risco_Score__c
                FROM Processo_Critico__c
                WHERE Id = :processoId
                WITH USER_MODE
                LIMIT 1
            ];
            if (ps.isEmpty()) {
                throw aura('Processo não encontrado ou sem acesso.');
            }
            Processo_Critico__c p = ps[0];
            Integer abertos = [
                SELECT COUNT()
                FROM Plano_Mitigacao__c
                WHERE Processo__c = :processoId AND Status__c IN :ABERTOS
                WITH USER_MODE
            ];
            if (abertos > 0) {
                throw aura('Este processo já tem um plano aberto.');
            }
            String obj = objetivoPara(p);
            if (obj == null) {
                throw aura('Este processo está coberto e com registro atualizado: não precisa de plano.');
            }

            Date hoje = Date.today();
            Plano_Mitigacao__c plano = new Plano_Mitigacao__c(
                Name = (ROTULO_OBJETIVO.get(obj) + ' — ' + p.Name).left(80),
                Processo__c = p.Id,
                Objetivo__c = obj,
                Status__c = RASCUNHO,
                Data_Alvo__c = hoje.addDays(PRAZO_PADRAO_DIAS),
                Score_Inicial__c = p.Risco_Score__c,
                Estado_Inicial__c = p.Estado_Cobertura__c
            );
            Database.insert(plano, AccessLevel.USER_MODE);

            List<Acao_Mitigacao__c> acoes = new List<Acao_Mitigacao__c>();
            Integer ordem = 1;
            for (List<Object> t : modelo(obj)) {
                acoes.add(
                    new Acao_Mitigacao__c(
                        Plano__c = plano.Id,
                        Name = (String) t[0],
                        Tipo__c = (String) t[1],
                        Prazo__c = hoje.addDays((Integer) t[2]),
                        Status__c = 'A fazer',
                        Ordem__c = ordem++
                    )
                );
            }
            Database.insert(acoes, AccessLevel.USER_MODE);
            return plano.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    /** Acoes padrao por objetivo: descricao, tipo, prazo em dias. */
    public static List<List<Object>> modelo(String objetivo) {
        if (objetivo == HABILITAR) {
            return new List<List<Object>>{
                new List<Object>{ 'Definir quem será o substituto', 'Validacao', 7 },
                new List<Object>{ 'Execução acompanhada do processo (2 ciclos)', 'Treinamento', 21 },
                new List<Object>{ 'Substituto executa sozinho com checklist; registrar a habilitação', 'Validacao', 30 }
            };
        }
        if (objetivo == REGISTRAR) {
            return new List<List<Object>>{
                new List<Object>{ 'Entrevista com quem executa', 'Registro', 7 },
                new List<Object>{ 'Redigir o passo a passo', 'Registro', 14 },
                new List<Object>{ 'Revisar e aprovar o registro', 'Validacao', 21 }
            };
        }
        if (objetivo == ATUALIZAR) {
            return new List<List<Object>>{
                new List<Object>{ 'Revisar o registro com quem executa', 'Registro', 7 },
                new List<Object>{ 'Publicar a versão revisada e atualizar a data de revisão', 'Validacao', 14 }
            };
        }
        return new List<List<Object>>{
            new List<Object>{ 'Levantar quem executa hoje e registrar as habilitações', 'Validacao', 7 },
            new List<Object>{ 'Estimar impacto por hora e horas para restabelecer', 'Validacao', 14 }
        };
    }

    @AuraEnabled
    public static void concluirAcao(Id acaoId) {
        try {
            Database.update(new Acao_Mitigacao__c(Id = acaoId, Status__c = ACAO_CONCLUIDA), AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    /** Em execucao, Concluido ou Cancelado. A regra de validacao protege a conclusao. */
    @AuraEnabled
    public static void mudarStatusPlano(Id planoId, String status) {
        if (status != EM_EXECUCAO && status != CONCLUIDO && status != CANCELADO) {
            throw aura('Status inválido: ' + status);
        }
        try {
            if (status == EM_EXECUCAO) {
                // Reabrir/iniciar nao pode criar um segundo plano aberto no mesmo processo.
                Plano_Mitigacao__c atual = [
                    SELECT Processo__c FROM Plano_Mitigacao__c WHERE Id = :planoId WITH USER_MODE LIMIT 1
                ];
                Integer outros = [
                    SELECT COUNT()
                    FROM Plano_Mitigacao__c
                    WHERE Processo__c = :atual.Processo__c AND Status__c IN :ABERTOS AND Id != :planoId
                    WITH USER_MODE
                ];
                if (outros > 0) {
                    throw aura('Este processo já tem outro plano aberto.');
                }
            }
            Database.update(new Plano_Mitigacao__c(Id = planoId, Status__c = status), AccessLevel.USER_MODE);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    // ============================================================ gatilho
    /** before insert/update de Acao_Mitigacao__c: carimba a data de conclusao. */
    public static void carimbarConclusao(List<Acao_Mitigacao__c> acoes) {
        for (Acao_Mitigacao__c a : acoes) {
            if (a.Status__c == ACAO_CONCLUIDA) {
                if (a.Concluida_Em__c == null) {
                    a.Concluida_Em__c = Date.today();
                }
            } else {
                a.Concluida_Em__c = null;
            }
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
        return aura(
            semAcesso
                ? 'SEM_PERMISSAO: seu usuário não tem acesso aos planos de mitigação. Peça o permission set EBL_RAIZ_Cockpit.'
                : m
        );
    }
}
