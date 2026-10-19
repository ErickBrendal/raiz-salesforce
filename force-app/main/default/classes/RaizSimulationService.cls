/**
 * RaizSimulationService
 * ---------------------------------------------------------------------------
 * Simulador de ausencia v2: "se esta pessoa faltar amanha, o que para?"
 *
 * Diferenca para o simulador v1 (RaizCockpitService.simularSaida): o v1 so
 * conhecia o DONO do processo e assumia que todo ponto unico do dono para.
 * Este recalcula sobre HABILITACOES: para cada processo em que a pessoa esta
 * apta, conta quem continua apto sem ela. O resultado separa tres efeitos:
 *
 *   PARA       — ela era a unica pessoa apta (sobram 0).
 *   FRAGIL     — sobra exatamente 1: o processo roda, mas vira ponto unico.
 *   CONTINUA   — sobram 2 ou mais: coberto por substitutos.
 *
 * NAO DESTRUTIVO: somente leitura (SELECT em USER_MODE). Nenhum registro e
 * criado ou alterado; o teste de integridade confere isso contando DML.
 */
public with sharing class RaizSimulationService {
    public static final String PARA = 'Para';
    public static final String FRAGIL = 'Fica frágil';
    public static final String CONTINUA = 'Continua coberto';

    public static final List<String> PREMISSAS = new List<String>{
        'A ausência começa agora e dura até o processo ser restabelecido.',
        'Só conta como apto quem tem habilitação Apto, vigente e está ativo.',
        'Um substituto apto assume sem perda de capacidade.',
        'Exposição = impacto por hora × horas para restabelecer, somente nos processos que param.',
        'Processos são somados como independentes: se dividem a mesma equipe ou janela, as horas podem se sobrepor.',
        'Nada é gravado: a simulação é somente leitura.'
    };

    public class LinhaSimulacao {
        @AuraEnabled
        public Id processoId;
        @AuraEnabled
        public String processo;
        @AuraEnabled
        public String area;
        @AuraEnabled
        public String criticidade;
        @AuraEnabled
        public String areaRotulo;
        @AuraEnabled
        public String criticidadeRotulo;
        @AuraEnabled
        public Integer aptosAntes;
        @AuraEnabled
        public Integer aptosDepois;
        @AuraEnabled
        public String efeito;
        @AuraEnabled
        public String substitutos;
        @AuraEnabled
        public Decimal exposicao;
        @AuraEnabled
        public Boolean exposicaoCompleta;
        @AuraEnabled
        public Decimal horas;
        @AuraEnabled
        public Integer scoreDepois;
        @AuraEnabled
        public String farolDepois;
    }

    public class Resultado {
        @AuraEnabled
        public String pessoa;
        @AuraEnabled
        public Integer processosAvaliados = 0;
        @AuraEnabled
        public Integer param = 0;
        @AuraEnabled
        public Integer ficamFrageis = 0;
        @AuraEnabled
        public Integer continuam = 0;
        @AuraEnabled
        public Decimal exposicao = 0;
        @AuraEnabled
        public Integer exposicaoIncompleta = 0;
        @AuraEnabled
        public Decimal horasParaRestabelecer = 0;
        @AuraEnabled
        public String veredito;
        @AuraEnabled
        public List<String> premissas = new List<String>();
        @AuraEnabled
        public List<String> ressalvas = new List<String>();
        @AuraEnabled
        public List<LinhaSimulacao> linhas = new List<LinhaSimulacao>();
    }

    public class Opcao {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public Integer habilitacoes;
    }

    // ------------------------------------------------------------ opcoes
    /** Profissionais ativos com ao menos uma habilitacao Apto, mais concentrados primeiro. */
    @AuraEnabled(cacheable=true)
    public static List<Opcao> getProfissionais(Id contaId) {
        try {
            List<AggregateResult> linhas;
            if (contaId == null) {
                linhas = [
                    SELECT Profissional__c pid, MAX(Profissional__r.Name) nome, COUNT(Id) qtd
                    FROM Habilitacao__c
                    WHERE Status__c = 'Apto' AND Profissional__r.Ativo__c = TRUE
                    WITH USER_MODE
                    GROUP BY Profissional__c
                    ORDER BY COUNT(Id) DESC, MAX(Profissional__r.Name)
                    LIMIT 100
                ];
            } else {
                linhas = [
                    SELECT Profissional__c pid, MAX(Profissional__r.Name) nome, COUNT(Id) qtd
                    FROM Habilitacao__c
                    WHERE Status__c = 'Apto' AND Profissional__r.Ativo__c = TRUE AND Processo__r.Conta__c = :contaId
                    WITH USER_MODE
                    GROUP BY Profissional__c
                    ORDER BY COUNT(Id) DESC, MAX(Profissional__r.Name)
                    LIMIT 100
                ];
            }
            List<Opcao> out = new List<Opcao>();
            for (AggregateResult ar : linhas) {
                Opcao o = new Opcao();
                o.value = String.valueOf(ar.get('pid'));
                o.habilitacoes = (Integer) ar.get('qtd');
                o.label = (String) ar.get('nome') + ' (' + qtd(o.habilitacoes, 'habilitação', 'habilitações') + ')';
                out.add(o);
            }
            return out;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    // ---------------------------------------------------------- simular
    @AuraEnabled(cacheable=true)
    public static Resultado simularAusencia(Id contaId, Id profissionalId) {
        if (profissionalId == null) {
            throw aura('Escolha um profissional para simular.');
        }
        try {
            return calcular(contaId, profissionalId, Date.today());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    @TestVisible
    private static Resultado calcular(Id contaId, Id profissionalId, Date hoje) {
        Resultado r = new Resultado();
        r.premissas.addAll(PREMISSAS);

        List<Profissional__c> pessoa = [
            SELECT Id, Name
            FROM Profissional__c
            WHERE Id = :profissionalId
            WITH USER_MODE
            LIMIT 1
        ];
        if (pessoa.isEmpty()) {
            throw aura('Profissional não encontrado ou sem acesso.');
        }
        r.pessoa = pessoa[0].Name;

        // Processos em que a pessoa esta apta e vigente hoje.
        Set<Id> processoIds = new Set<Id>();
        for (Habilitacao__c h : [
            SELECT Processo__c, Status__c, Valida_Ate__c, Profissional__r.Ativo__c
            FROM Habilitacao__c
            WHERE Profissional__c = :profissionalId AND Status__c = 'Apto'
            WITH USER_MODE
            LIMIT 500
        ]) {
            if (RaizRiskEngine.vigente(h.Status__c, h.Profissional__r.Ativo__c, h.Valida_Ate__c, hoje)) {
                processoIds.add(h.Processo__c);
            }
        }

        List<Processo_Critico__c> procs;
        if (contaId == null) {
            procs = consultarProcessos(processoIds);
        } else {
            procs = consultarProcessosDaConta(processoIds, contaId);
        }

        for (Processo_Critico__c p : procs) {
            Integer antes = 0;
            List<String> subs = new List<String>();
            for (Habilitacao__c h : p.Habilitacoes__r) {
                if (!RaizRiskEngine.vigente(h.Status__c, h.Profissional__r.Ativo__c, h.Valida_Ate__c, hoje)) {
                    continue;
                }
                antes++;
                if (h.Profissional__c != profissionalId) {
                    subs.add(h.Profissional__r.Name);
                }
            }
            Integer depois = antes - 1;

            RaizRiskEngine.Avaliacao a = RaizRiskEngine.avaliar(p, depois);
            LinhaSimulacao l = new LinhaSimulacao();
            l.processoId = p.Id;
            l.processo = p.Name;
            l.area = p.Area__c;
            l.criticidade = p.Criticidade__c;
            l.areaRotulo = RaizCockpitService.rotulo(Processo_Critico__c.Area__c, p.Area__c);
            l.criticidadeRotulo = RaizCockpitService.rotulo(Processo_Critico__c.Criticidade__c, p.Criticidade__c);
            l.aptosAntes = antes;
            l.aptosDepois = depois;
            l.substitutos = subs.isEmpty() ? 'Ninguém' : String.join(subs, ', ');
            l.scoreDepois = a.score;
            l.farolDepois = a.farol;
            l.horas = p.Horas_Para_Restabelecer__c;
            l.exposicao = 0;
            l.exposicaoCompleta = true;

            if (depois <= 0) {
                l.efeito = PARA;
                l.exposicao = a.exposicao;
                l.exposicaoCompleta = a.exposicaoCompleta;
                r.param++;
                r.exposicao += a.exposicao;
                r.horasParaRestabelecer += (p.Horas_Para_Restabelecer__c == null) ? 0 : p.Horas_Para_Restabelecer__c;
                if (!a.exposicaoCompleta) {
                    r.exposicaoIncompleta++;
                }
            } else if (depois == 1) {
                l.efeito = FRAGIL;
                r.ficamFrageis++;
            } else {
                l.efeito = CONTINUA;
                r.continuam++;
            }
            r.linhas.add(l);
        }
        r.processosAvaliados = r.linhas.size();
        ordenar(r.linhas);

        if (r.exposicaoIncompleta > 0) {
            r.ressalvas.add(
                qtd(r.exposicaoIncompleta, 'processo que para não tem', 'processos que param não têm') +
                    ' impacto por hora ou horas para restabelecer: a exposição está subestimada.'
            );
        }
        if (r.processosAvaliados == 0) {
            r.ressalvas.add(
                'Nenhuma habilitação Apto e vigente desta pessoa neste recorte. Zero aqui é ausência de evidência, não garantia de cobertura.'
            );
        }
        r.veredito = veredito(r);
        return r;
    }

    private static List<Processo_Critico__c> consultarProcessos(Set<Id> ids) {
        return [
            SELECT
                Id,
                Name,
                Area__c,
                Criticidade__c,
                Impacto_Hora__c,
                Horas_Para_Restabelecer__c,
                Atualizado__c,
                (
                    SELECT Profissional__c, Profissional__r.Name, Profissional__r.Ativo__c, Status__c, Valida_Ate__c
                    FROM Habilitacoes__r
                    WHERE Status__c = 'Apto'
                    ORDER BY Profissional__r.Name
                )
            FROM Processo_Critico__c
            WHERE Id IN :ids
            WITH USER_MODE
            LIMIT 500
        ];
    }

    private static List<Processo_Critico__c> consultarProcessosDaConta(Set<Id> ids, Id contaId) {
        return [
            SELECT
                Id,
                Name,
                Area__c,
                Criticidade__c,
                Impacto_Hora__c,
                Horas_Para_Restabelecer__c,
                Atualizado__c,
                (
                    SELECT Profissional__c, Profissional__r.Name, Profissional__r.Ativo__c, Status__c, Valida_Ate__c
                    FROM Habilitacoes__r
                    WHERE Status__c = 'Apto'
                    ORDER BY Profissional__r.Name
                )
            FROM Processo_Critico__c
            WHERE Id IN :ids AND Conta__c = :contaId
            WITH USER_MODE
            LIMIT 500
        ];
    }

    /** Para > Fica fragil > Continua; dentro do grupo, maior exposicao/score primeiro. */
    private static void ordenar(List<LinhaSimulacao> ls) {
        Map<String, Integer> peso = new Map<String, Integer>{ PARA => 0, FRAGIL => 1, CONTINUA => 2 };
        for (Integer i = 0; i < ls.size(); i++) {
            for (Integer j = i + 1; j < ls.size(); j++) {
                LinhaSimulacao a = ls[i];
                LinhaSimulacao b = ls[j];
                Boolean trocar =
                    peso.get(b.efeito) < peso.get(a.efeito) ||
                    (peso.get(b.efeito) == peso.get(a.efeito) &&
                    (b.exposicao > a.exposicao || (b.exposicao == a.exposicao && b.scoreDepois > a.scoreDepois)));
                if (trocar) {
                    ls[i] = b;
                    ls[j] = a;
                }
            }
        }
    }

    @TestVisible
    private static String veredito(Resultado r) {
        if (r.processosAvaliados == 0) {
            return 'Sem habilitação registrada para esta pessoa: não dá para afirmar que nada para.';
        }
        if (r.param == 0 && r.ficamFrageis == 0) {
            return 'Nada para. ' +
                (r.processosAvaliados == 1
                    ? 'O processo continua com ao menos duas pessoas aptas.'
                    : 'Os ' + r.processosAvaliados + ' processos continuam com ao menos duas pessoas aptas.');
        }
        if (r.param == 0) {
            return 'Nada para hoje, mas ' +
                qtd(r.ficamFrageis, 'processo passa', 'processos passam') +
                ' a depender de uma única pessoa. Prioridade: habilitar um segundo substituto.';
        }
        String base =
            qtd(r.param, 'processo para', 'processos param') +
            (r.ficamFrageis > 0 ? ' e ' + qtd(r.ficamFrageis, 'fica frágil', 'ficam frágeis') : '') +
            '. Tempo para restabelecer: ' +
            r.horasParaRestabelecer.setScale(0) +
            ' h úteis.';
        return (r.param >= 3)
            ? 'Concentração crítica. ' + base + ' Recomendado: plano de sucessão com registro e substituto treinado.'
            : 'Exposição contida, mas existente. ' + base + ' Recomendado: habilitar substituto nos processos que param.';
    }

    /** "1 processo" / "2 processos". */
    @TestVisible
    private static String qtd(Integer n, String singular, String plural) {
        return n + ' ' + (n == 1 ? singular : plural);
    }


    /** AuraHandledException so expoe a mensagem em getMessage() com setMessage(). */
    private static AuraHandledException aura(String m) {
        AuraHandledException e = new AuraHandledException(m);
        e.setMessage(m);
        return e;
    }

    private static AuraHandledException erroAmigavel(Exception e) {
        String m = e.getMessage();
        String texto = (m != null &&
            (m.containsIgnoreCase('access') ||
            m.containsIgnoreCase('No such column') ||
            m.containsIgnoreCase('not supported') ||
            m.containsIgnoreCase('permission')))
            ? 'SEM_PERMISSAO: seu usuário não tem acesso a Habilitações/Profissionais. Peça o permission set EBL_RAIZ_Cockpit.'
            : 'Não foi possível simular: ' + m;
        return aura(texto);
    }
}
