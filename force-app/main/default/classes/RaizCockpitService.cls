/**
 * RaizCockpitService
 * ---------------------------------------------------------------------------
 * Camada de leitura do Cockpit Executivo do Metodo RAIZ (EBL Solucoes).
 *
 * POR QUE ESTA CLASSE EXISTE
 * O documento de arquitetura da EBL diz que consultoria de conhecimento morre
 * por nao ter metrica. Tres indicadores resolvem:
 *
 *   1. COBERTURA CRITICA   - % dos processos criticos com registro atualizado
 *                            e dono definido. Sai de zero e sobe a cada entrega.
 *   2. INDICE DE DEPENDENCIA - nº de processos criticos com UMA unica pessoa
 *                            capaz de executar. E o numero que assusta a diretoria.
 *   3. ATUALIDADE DO ACERVO - % de documentos revisados dentro do prazo.
 *                            Prova que a zeladoria esta sendo entregue.
 *
 * Esta classe calcula os tres a partir do dado real, nao de declaracao.
 *
 * O QUARTO NUMERO - O QUE FAZ O DIRETOR ASSINAR
 * Indicador de processo nao move orcamento. Dinheiro move. Por isso existe a
 * EXPOSICAO FINANCEIRA: horas para restabelecer x custo da hora parada, somado
 * apenas nos processos com ponto unico de falha. Traduz risco de conhecimento
 * em reais, que e a lingua do financeiro.
 *
 * SEGURANCA
 * 'with sharing' + AccessLevel.USER_MODE: o cockpit mostra apenas o que o
 * usuario pode ver. Um painel executivo que ignora compartilhamento vira
 * vazamento de dado com aparencia de dashboard.
 */
public with sharing class RaizCockpitService {

    // =====================================================================
    // DTOs
    // =====================================================================
    public class Indicador {
        @AuraEnabled public String chave;
        @AuraEnabled public String rotulo;
        @AuraEnabled public Decimal valor;
        @AuraEnabled public String valorFormatado;
        @AuraEnabled public String unidade;
        @AuraEnabled public String explicacao;
        @AuraEnabled public String tom;      // bom | atencao | critico
    }

    public class LinhaRisco {
        @AuraEnabled public Id     id;
        @AuraEnabled public String processo;
        @AuraEnabled public String area;
        @AuraEnabled public String criticidade;
        @AuraEnabled public String dono;
        @AuraEnabled public Integer pessoasAptas;
        @AuraEnabled public Boolean pontoUnico;
        @AuraEnabled public Boolean atualizado;
        @AuraEnabled public Boolean aplicadoNoSistema;
        @AuraEnabled public String sistemaOrigem;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String farol;
        @AuraEnabled public Decimal exposicao;
        @AuraEnabled public String exposicaoFmt;
        @AuraEnabled public String estadoCobertura;   // Sem cobertura | Ponto unico | Coberto | Informacao insuficiente
        @AuraEnabled public String fonteCobertura;    // Habilitacoes | Declarado | Sem dado
        @AuraEnabled public Boolean exposicaoCompleta;
        @AuraEnabled public String areaRotulo;
        @AuraEnabled public String criticidadeRotulo;
        @AuraEnabled public String aptosTexto;        // '—' quando nao ha informacao
    }

    public class PessoaChave {
        @AuraEnabled public Id     userId;
        @AuraEnabled public String nome;
        @AuraEnabled public Integer processosSozinho;
        @AuraEnabled public Integer processosTotal;
        @AuraEnabled public Decimal exposicao;
        @AuraEnabled public String exposicaoFmt;
        @AuraEnabled public Decimal percentualDaExposicao;
    }

    public class Fatia {
        @AuraEnabled public String rotulo;
        @AuraEnabled public Integer quantidade;
        @AuraEnabled public Decimal valor;
        @AuraEnabled public Decimal percentual;
        @AuraEnabled public String rotuloExibicao;
    }

    public class Cockpit {
        @AuraEnabled public String cliente;
        @AuraEnabled public Integer totalProcessos;
        @AuraEnabled public List<Indicador>  indicadores   = new List<Indicador>();
        @AuraEnabled public List<LinhaRisco> topRiscos     = new List<LinhaRisco>();
        @AuraEnabled public List<PessoaChave> pessoasChave = new List<PessoaChave>();
        @AuraEnabled public List<Fatia> porArea            = new List<Fatia>();
        @AuraEnabled public List<Fatia> porFaseRaiz        = new List<Fatia>();
        @AuraEnabled public List<Fatia> ondeVive           = new List<Fatia>();
        @AuraEnabled public List<Fatia> matrizRisco        = new List<Fatia>();
        @AuraEnabled public String geradoEm;
        @AuraEnabled public List<String> ressalvas         = new List<String>();
        // Onda 1 — motor de risco
        @AuraEnabled public Integer informacaoInsuficiente = 0;
        @AuraEnabled public Integer coberturaEvidenciada   = 0;  // processos com aptos vindos de habilitacao
        @AuraEnabled public Integer coberturaDeclarada     = 0;  // processos com aptos so declarados
        @AuraEnabled public Integer exposicaoIncompleta    = 0;
        @AuraEnabled public List<Fatia> estadosCobertura   = new List<Fatia>();
        // Onda 4 — cockpit v2
        @AuraEnabled public Boolean semPermissao           = false;
        @AuraEnabled public Integer planosAbertos          = 0;
        @AuraEnabled public Integer planosAtrasados        = 0;
        @AuraEnabled public Integer processosComPlano      = 0;
        @AuraEnabled public Integer scoreInicialPlanos     = 0;  // soma dos scores na criacao dos planos abertos
        @AuraEnabled public Integer scoreAtualPlanos       = 0;  // soma dos scores atuais dos mesmos processos
        @AuraEnabled public Integer pontosUnicosSemPlano   = 0;
        // Onda 7 — governanca documental (documentos "Em Analise" dos processos do recorte)
        @AuraEnabled public Integer govEmRevisao           = 0;
        @AuraEnabled public Integer govAtrasadas           = 0;  // prazo da revisao ja passou
        @AuraEnabled public Integer govBloqueadas          = 0;  // a automacao barrou o encaminhamento
        @AuraEnabled public Integer govSemPrazo            = 0;
    }

    public class ResultadoSimulacao {
        @AuraEnabled public String pessoa;
        @AuraEnabled public Integer processosParados;
        @AuraEnabled public Decimal exposicao;
        @AuraEnabled public String exposicaoFmt;
        @AuraEnabled public Integer horasParaRestabelecer;
        @AuraEnabled public String tempoLegivel;
        @AuraEnabled public List<LinhaRisco> processos = new List<LinhaRisco>();
        @AuraEnabled public String veredito;
    }

    // =====================================================================
    // Utilitarios
    // =====================================================================
    private static String moeda(Decimal v) {
        if (v == null) v = 0;
        // Formatacao pt-BR feita no Apex para nao depender de locale do browser.
        // Independente do locale do usuario: o separador e montado aqui.
        // (A versao anterior trocava ',' por '.' e invertia o resultado quando
        // o usuario passava a usar locale pt_BR.)
        Long n = v.setScale(0, System.RoundingMode.HALF_UP).longValue();
        String d = String.valueOf(Math.abs(n));
        String out = '';
        while (d.length() > 3) {
            out = '.' + d.right(3) + out;
            d = d.left(d.length() - 3);
        }
        return 'R$ ' + (n < 0 ? '-' : '') + d + out;
    }

    /** "1 processo" / "2 processos" — concordancia no texto exibido. */
    @TestVisible
    private static String qtd(Integer n, String singular, String plural) {
        return n + ' ' + (n == 1 ? singular : plural);
    }

    /** Rotulo de exibicao (com acento) a partir do valor gravado do picklist. */
    private static Map<String, Map<String, String>> rotulosCache = new Map<String, Map<String, String>>();
    public static String rotulo(Schema.SObjectField campo, String valor) {
        if (valor == null) return null;
        String chave = String.valueOf(campo);
        if (!rotulosCache.containsKey(chave)) {
            Map<String, String> m = new Map<String, String>();
            for (Schema.PicklistEntry e : campo.getDescribe().getPicklistValues()) {
                m.put(e.getValue(), e.getLabel());
            }
            rotulosCache.put(chave, m);
        }
        String r = rotulosCache.get(chave).get(valor);
        return r == null ? valor : r;
    }

    private static final Map<String, String> ROTULO_FAROL = new Map<String, String>{
        'Critico' => 'Crítico', 'Alto' => 'Alto', 'Medio' => 'Médio', 'Baixo' => 'Baixo' };

    private static Indicador ind(String chave, String rotulo, Decimal valor,
                                 String fmt, String unidade, String expl, String tom) {
        Indicador i = new Indicador();
        i.chave = chave; i.rotulo = rotulo; i.valor = valor;
        i.valorFormatado = fmt; i.unidade = unidade;
        i.explicacao = expl; i.tom = tom;
        return i;
    }

    // =====================================================================
    // COCKPIT
    // =====================================================================
    @AuraEnabled(cacheable=true)
    public static Cockpit getCockpit(Id contaId) {
        Cockpit c = new Cockpit();
        c.geradoEm = Datetime.now().format('dd/MM/yyyy HH:mm');

        List<Processo_Critico__c> procs;
        try {
            if (contaId == null) {
                procs = [
                    SELECT Id, Name, Area__c, Criticidade__c, Peso_Criticidade__c,
                           Dono__c, Dono__r.Name, Pessoas_Aptas__c, Ponto_Unico_de_Falha__c,
                           Status_Registro__c, Atualizado__c, Aplicado_no_Sistema__c,
                           Sistema_Origem__c, Risco_Score__c, Farol__c,
                           Exposicao_Financeira__c, Horas_Para_Restabelecer__c,
                           Aptos_Efetivos__c, Estado_Cobertura__c, Fonte_Cobertura__c,
                           Exposicao_Completa__c,
                           Conta__r.Name, Engajamento__r.Fase_RAIZ__c
                    FROM Processo_Critico__c
                    WITH USER_MODE
                    ORDER BY Risco_Score__c DESC NULLS LAST
                    LIMIT 2000
                ];
                c.cliente = 'Todos os clientes';
            } else {
                procs = [
                    SELECT Id, Name, Area__c, Criticidade__c, Peso_Criticidade__c,
                           Dono__c, Dono__r.Name, Pessoas_Aptas__c, Ponto_Unico_de_Falha__c,
                           Status_Registro__c, Atualizado__c, Aplicado_no_Sistema__c,
                           Sistema_Origem__c, Risco_Score__c, Farol__c,
                           Exposicao_Financeira__c, Horas_Para_Restabelecer__c,
                           Aptos_Efetivos__c, Estado_Cobertura__c, Fonte_Cobertura__c,
                           Exposicao_Completa__c,
                           Conta__r.Name, Engajamento__r.Fase_RAIZ__c
                    FROM Processo_Critico__c
                    WHERE Conta__c = :contaId
                    WITH USER_MODE
                    ORDER BY Risco_Score__c DESC NULLS LAST
                    LIMIT 2000
                ];
                c.cliente = procs.isEmpty() ? 'Cliente sem processos mapeados' : procs[0].Conta__r.Name;
            }
        } catch (Exception e) {
            // USER_MODE faz a consulta FALHAR quando falta FLS — nao retorna branco.
            // Dizer isso e melhor que mostrar um painel vazio que parece correto.
            c.semPermissao = true;
            c.ressalvas.add('Não foi possível ler os processos: ' + e.getMessage() +
                            ' — verifique o permission set EBL_RAIZ_Cockpit.');
            return c;
        }

        c.totalProcessos = procs.size();
        if (procs.isEmpty()) {
            c.ressalvas.add('Nenhum processo mapeado neste recorte. Os indicadores abaixo são zero por ausência de dado, não por ausência de risco.');
        }

        // ---- contadores ----
        Integer criticos = 0, criticosCobertos = 0, pontoUnico = 0, registrados = 0,
                atualizados = 0, noSistema = 0, semDono = 0;
        Decimal exposicaoTotal = 0;

        Map<String,Integer> porArea = new Map<String,Integer>();
        Map<String,Integer> ondeVive = new Map<String,Integer>();
        Map<String,Integer> porFarol = new Map<String,Integer>{
            'Critico'=>0,'Alto'=>0,'Medio'=>0,'Baixo'=>0 };
        Map<String,Integer> porFase = new Map<String,Integer>();
        Map<Id,PessoaChave> pessoas = new Map<Id,PessoaChave>();
        Map<String,Integer> porEstado = new Map<String,Integer>();

        for (Processo_Critico__c p : procs) {
            Boolean ehCritico = (p.Criticidade__c == 'Critico' || p.Criticidade__c == 'Alto');
            if (ehCritico) criticos++;

            Boolean temDono = (p.Dono__c != null);
            if (!temDono) semDono++;

            Boolean atual = (p.Atualizado__c == true);
            if (atual) atualizados++;
            if (p.Status_Registro__c == 'Registrado') registrados++;
            if (ehCritico && atual && temDono) criticosCobertos++;
            if (p.Ponto_Unico_de_Falha__c == true) pontoUnico++;
            if (p.Aplicado_no_Sistema__c == true) noSistema++;

            String est = String.isBlank(p.Estado_Cobertura__c) ? RaizRiskEngine.INSUFICIENTE : p.Estado_Cobertura__c;
            porEstado.put(est, (porEstado.containsKey(est) ? porEstado.get(est) : 0) + 1);
            if (est == RaizRiskEngine.INSUFICIENTE) c.informacaoInsuficiente++;
            if (p.Fonte_Cobertura__c == RaizRiskEngine.FONTE_HABILITACOES) c.coberturaEvidenciada++;
            if (p.Fonte_Cobertura__c == RaizRiskEngine.FONTE_DECLARADO) c.coberturaDeclarada++;
            if (p.Exposicao_Completa__c == false) c.exposicaoIncompleta++;

            Decimal exp = (p.Exposicao_Financeira__c == null) ? 0 : p.Exposicao_Financeira__c;
            exposicaoTotal += exp;

            String a = String.isBlank(p.Area__c) ? 'Sem área' : p.Area__c;
            porArea.put(a, (porArea.containsKey(a) ? porArea.get(a) : 0) + 1);

            String o = String.isBlank(p.Sistema_Origem__c) ? 'Não informado' : p.Sistema_Origem__c;
            ondeVive.put(o, (ondeVive.containsKey(o) ? ondeVive.get(o) : 0) + 1);

            String f = String.isBlank(p.Farol__c) ? 'Baixo' : p.Farol__c;
            if (porFarol.containsKey(f)) porFarol.put(f, porFarol.get(f) + 1);

            String fase = (p.Engajamento__r != null && p.Engajamento__r.Fase_RAIZ__c != null)
                          ? p.Engajamento__r.Fase_RAIZ__c : 'Sem engajamento';
            porFase.put(fase, (porFase.containsKey(fase) ? porFase.get(fase) : 0) + 1);

        }

        // ---- pessoas-chave por HABILITACAO (Onda 3) ----
        // Quem e o unico apto de cada processo. Antes era o dono do processo,
        // o que confundia responsabilidade formal com capacidade de executar.
        Integer pontoUnicoSemPessoa = 0;
        try {
            pontoUnicoSemPessoa = atribuirPessoas(procs, pessoas);
        } catch (Exception e) {
            c.ressalvas.add('Concentração de conhecimento indisponível: sem acesso às habilitações (' + e.getMessage() + ').');
        }

        // ---- os tres indicadores do metodo + o quarto ----
        Decimal cobertura = (criticos == 0) ? 0
            : (Decimal.valueOf(criticosCobertos) / criticos * 100).setScale(0, System.RoundingMode.HALF_UP);
        Decimal atualidade = (procs.isEmpty()) ? 0
            : (Decimal.valueOf(atualizados) / procs.size() * 100).setScale(0, System.RoundingMode.HALF_UP);
        Decimal pctSistema = (procs.isEmpty()) ? 0
            : (Decimal.valueOf(noSistema) / procs.size() * 100).setScale(0, System.RoundingMode.HALF_UP);

        c.indicadores.add(ind('dependencia', 'Índice de dependência', pontoUnico,
            String.valueOf(pontoUnico), 'processos',
            'Processos que dependem de até uma pessoa apta (0 ou 1). Se ela faltar, o processo para.',
            pontoUnico == 0 ? ((c.informacaoInsuficiente == 0 && !procs.isEmpty()) ? 'bom' : 'atencao')
                            : (pontoUnico <= 3 ? 'atencao' : 'critico')));

        c.indicadores.add(ind('exposicao', 'Exposição financeira', exposicaoTotal,
            moeda(exposicaoTotal), 'em risco',
            'Horas para restabelecer × custo da hora parada, somado só nos processos de ponto único de falha.',
            exposicaoTotal == 0 ? ((c.informacaoInsuficiente == 0 && c.exposicaoIncompleta == 0 && !procs.isEmpty()) ? 'bom' : 'atencao')
                                : (exposicaoTotal < 100000 ? 'atencao' : 'critico')));

        c.indicadores.add(ind('cobertura', 'Cobertura crítica', cobertura,
            String.valueOf(cobertura.intValue()) + '%', 'dos críticos',
            'Processos críticos e altos com registro atualizado e dono definido.',
            cobertura >= 80 ? 'bom' : (cobertura >= 40 ? 'atencao' : 'critico')));

        c.indicadores.add(ind('atualidade', 'Atualidade do acervo', atualidade,
            String.valueOf(atualidade.intValue()) + '%', 'no prazo',
            'Registros revisados dentro do prazo de validade. Registro vencido não conta.',
            atualidade >= 80 ? 'bom' : (atualidade >= 50 ? 'atencao' : 'critico')));

        c.indicadores.add(ind('sistema', 'Aplicado no sistema', pctSistema,
            String.valueOf(pctSistema.intValue()) + '%', 'dos processos',
            'Processos cujo conhecimento está aplicado no próprio sistema (campo, validação, texto de ajuda ou fluxo), e não só em documento.',
            pctSistema >= 60 ? 'bom' : (pctSistema >= 25 ? 'atencao' : 'critico')));

        // ---- ressalvas do motor de risco (Onda 1) ----
        if (c.informacaoInsuficiente > 0) {
            c.ressalvas.add(qtd(c.informacaoInsuficiente, 'processo', 'processos') + ' sem informação de pessoas aptas (nem habilitação, nem declarado). Não entram como cobertos nem como ponto único — e pesam como ponto único no score.');
        }
        if (c.exposicaoIncompleta > 0) {
            c.ressalvas.add(qtd(c.exposicaoIncompleta, 'ponto único', 'pontos únicos') + ' sem impacto por hora ou horas para restabelecer: a exposição exibida está subestimada.');
        }
        if (c.coberturaDeclarada > 0) {
            c.ressalvas.add(qtd(c.coberturaDeclarada, 'processo', 'processos') + ' com pessoas aptas apenas declaradas, sem habilitação registrada.');
        }
        if (exposicaoTotal > 0) {
            c.ressalvas.add('Premissa da exposição: impacto por hora × horas para restabelecer, somente em ponto único, somando processos como independentes. Paradas simultâneas podem se sobrepor.');
        }

        if (pontoUnicoSemPessoa > 0) {
            c.ressalvas.add(qtd(pontoUnicoSemPessoa, 'ponto único não aparece', 'pontos únicos não aparecem') + ' em Concentração de conhecimento: não há uma pessoa apta habilitada para atribuir.');
        }

        if (semDono > 0) {
            c.ressalvas.add(qtd(semDono, 'processo', 'processos') + ' sem dono definido. Entra na cobertura como não coberto.');
        }

        // ---- top riscos ----
        Integer n = 0;
        for (Processo_Critico__c p : procs) {
            if (n >= 12) break;
            c.topRiscos.add(linha(p));
            n++;
        }

        // ---- pessoas-chave, ordenadas por exposicao ----
        List<PessoaChave> lst = pessoas.values();
        for (PessoaChave pc : lst) {
            pc.exposicaoFmt = moeda(pc.exposicao);
            pc.percentualDaExposicao = (exposicaoTotal == 0) ? 0
                : (pc.exposicao / exposicaoTotal * 100).setScale(0, System.RoundingMode.HALF_UP);
        }
        for (Integer i = 0; i < lst.size(); i++) {
            for (Integer j = i + 1; j < lst.size(); j++) {
                if (lst[j].processosSozinho > lst[i].processosSozinho ||
                    (lst[j].processosSozinho == lst[i].processosSozinho && lst[j].exposicao > lst[i].exposicao)) {
                    PessoaChave t = lst[i]; lst[i] = lst[j]; lst[j] = t;
                }
            }
        }
        for (Integer i = 0; i < lst.size() && i < 8; i++) c.pessoasChave.add(lst[i]);

        c.porArea      = fatias(porArea, procs.size());
        c.ondeVive     = fatias(ondeVive, procs.size());
        c.porFaseRaiz  = fatias(porFase, procs.size());
        c.matrizRisco  = fatias(porFarol, procs.size());
        for (Fatia f : c.porArea)     f.rotuloExibicao = rotulo(Processo_Critico__c.Area__c, f.rotulo);
        for (Fatia f : c.ondeVive)    f.rotuloExibicao = rotulo(Processo_Critico__c.Sistema_Origem__c, f.rotulo);
        for (Fatia f : c.porFaseRaiz) f.rotuloExibicao = f.rotulo;
        for (Fatia f : c.matrizRisco) f.rotuloExibicao = ROTULO_FAROL.containsKey(f.rotulo) ? ROTULO_FAROL.get(f.rotulo) : f.rotulo;
        c.estadosCobertura = estadosFixos(porEstado, procs.size());
        resumirPlanos(c, procs);
        resumirGovernanca(c, procs);

        return c;
    }

    /**
     * Preenche 'pessoas' com, para cada profissional, em quantos processos ele
     * e o UNICO apto (status Apto, mesma regra do roll-up) e quanto de exposicao
     * isso representa. Devolve quantos pontos unicos ficaram sem pessoa.
     */
    private static Integer atribuirPessoas(List<Processo_Critico__c> procs, Map<Id, PessoaChave> pessoas) {
        Map<Id, Processo_Critico__c> porId = new Map<Id, Processo_Critico__c>(procs);
        Map<Id, List<Habilitacao__c>> aptosPorProcesso = new Map<Id, List<Habilitacao__c>>();
        for (Habilitacao__c h : [
            SELECT Processo__c, Profissional__c, Profissional__r.Name
            FROM Habilitacao__c
            WHERE Processo__c IN :porId.keySet() AND Status__c = 'Apto'
            WITH USER_MODE
            LIMIT 10000
        ]) {
            if (!aptosPorProcesso.containsKey(h.Processo__c)) aptosPorProcesso.put(h.Processo__c, new List<Habilitacao__c>());
            aptosPorProcesso.get(h.Processo__c).add(h);
        }
        Integer semPessoa = 0;
        for (Processo_Critico__c p : procs) {
            List<Habilitacao__c> aptos = aptosPorProcesso.get(p.Id);
            Boolean pu = (p.Ponto_Unico_de_Falha__c == true);
            if (aptos == null || aptos.isEmpty()) {
                if (pu) semPessoa++;
                continue;
            }
            for (Habilitacao__c h : aptos) {
                PessoaChave pc = pessoas.get(h.Profissional__c);
                if (pc == null) {
                    pc = new PessoaChave();
                    pc.userId = h.Profissional__c;
                    pc.nome = h.Profissional__r.Name;
                    pc.processosSozinho = 0; pc.processosTotal = 0; pc.exposicao = 0;
                    pessoas.put(h.Profissional__c, pc);
                }
                pc.processosTotal++;
                if (pu && aptos.size() == 1) {
                    pc.processosSozinho++;
                    pc.exposicao += (p.Exposicao_Financeira__c == null) ? 0 : p.Exposicao_Financeira__c;
                }
            }
            if (pu && aptos.size() != 1) semPessoa++;
        }
        return semPessoa;
    }

    /** Os quatro estados sempre presentes, na ordem de gravidade, com rotulo acentuado. */
    private static final List<String> ORDEM_ESTADOS = new List<String>{
        RaizRiskEngine.SEM_COBERTURA, RaizRiskEngine.PONTO_UNICO, RaizRiskEngine.INSUFICIENTE, RaizRiskEngine.COBERTO };
    private static final Map<String, String> ROTULO_ESTADO = new Map<String, String>{
        RaizRiskEngine.SEM_COBERTURA => 'Sem cobertura',
        RaizRiskEngine.PONTO_UNICO => 'Ponto único',
        RaizRiskEngine.INSUFICIENTE => 'Informação insuficiente',
        RaizRiskEngine.COBERTO => 'Coberto' };

    @TestVisible
    private static List<Fatia> estadosFixos(Map<String, Integer> porEstado, Integer total) {
        List<Fatia> out = new List<Fatia>();
        for (String e : ORDEM_ESTADOS) {
            Fatia f = new Fatia();
            f.rotulo = e;
            f.rotuloExibicao = ROTULO_ESTADO.get(e);
            f.quantidade = porEstado.containsKey(e) ? porEstado.get(e) : 0;
            f.percentual = (total == 0) ? 0
                : (Decimal.valueOf(f.quantidade) / total * 100).setScale(0, System.RoundingMode.HALF_UP);
            out.add(f);
        }
        return out;
    }

    /**
     * Planos abertos dos processos do recorte e a reducao de risco:
     * soma do score quando o plano nasceu x soma do score atual.
     * Falha de acesso aos planos nao derruba o cockpit: vira ressalva.
     */
    private static void resumirPlanos(Cockpit c, List<Processo_Critico__c> procs) {
        Map<Id, Processo_Critico__c> porId = new Map<Id, Processo_Critico__c>(procs);
        Set<Id> comPlano = new Set<Id>();
        try {
            for (Plano_Mitigacao__c pl : [
                SELECT Processo__c, Atrasado__c, Score_Inicial__c
                FROM Plano_Mitigacao__c
                WHERE Processo__c IN :porId.keySet() AND Status__c IN ('Rascunho', 'Em execucao')
                WITH USER_MODE
                LIMIT 2000
            ]) {
                c.planosAbertos++;
                if (pl.Atrasado__c == true) c.planosAtrasados++;
                if (comPlano.add(pl.Processo__c)) {
                    Processo_Critico__c p = porId.get(pl.Processo__c);
                    c.scoreInicialPlanos += (pl.Score_Inicial__c == null) ? 0 : pl.Score_Inicial__c.intValue();
                    c.scoreAtualPlanos += (p.Risco_Score__c == null) ? 0 : p.Risco_Score__c.intValue();
                }
            }
        } catch (Exception e) {
            c.ressalvas.add('Planos de mitigação indisponíveis: sem acesso (' + e.getMessage() + ').');
            return;
        }
        c.processosComPlano = comPlano.size();
        for (Processo_Critico__c p : procs) {
            if (p.Ponto_Unico_de_Falha__c == true && !comPlano.contains(p.Id)) c.pontosUnicosSemPlano++;
        }
    }

    /**
     * Onda 7: documentos em revisao dos processos do recorte. Regras:
     * atrasada = Prazo_Revisao__c < hoje; bloqueada = Governanca_Status__c
     * comeca com "Bloqueado" (gravado so pela automacao); sem prazo = prazo vazio.
     * Falha de acesso vira ressalva, como nos planos.
     */
    private static void resumirGovernanca(Cockpit c, List<Processo_Critico__c> procs) {
        Set<Id> ids = new Map<Id, Processo_Critico__c>(procs).keySet();
        Date hoje = Date.today();
        try {
            for (Business_Rule__c d : [
                SELECT Prazo_Revisao__c, Governanca_Status__c
                FROM Business_Rule__c
                WHERE Processo_Critico__c IN :ids AND Status__c = 'Em Analise'
                WITH USER_MODE
                LIMIT 2000
            ]) {
                c.govEmRevisao++;
                if (d.Prazo_Revisao__c == null) c.govSemPrazo++;
                else if (d.Prazo_Revisao__c < hoje) c.govAtrasadas++;
                if (d.Governanca_Status__c != null && d.Governanca_Status__c.startsWith('Bloqueado')) c.govBloqueadas++;
            }
        } catch (Exception e) {
            c.ressalvas.add('Governança documental indisponível: sem acesso (' + e.getMessage() + ').');
        }
    }

    private static LinhaRisco linha(Processo_Critico__c p) {
        LinhaRisco l = new LinhaRisco();
        l.id = p.Id;
        l.processo = p.Name;
        l.area = p.Area__c;
        l.criticidade = p.Criticidade__c;
        l.dono = (p.Dono__c == null) ? 'Sem dono' : p.Dono__r.Name;
        // Regra 4: sem informacao fica nulo — nunca vira 0 nem numero inventado.
        l.pessoasAptas = (p.Aptos_Efetivos__c == null) ? null : p.Aptos_Efetivos__c.intValue();
        l.pontoUnico = (p.Ponto_Unico_de_Falha__c == true);
        l.atualizado = (p.Atualizado__c == true);
        l.aplicadoNoSistema = (p.Aplicado_no_Sistema__c == true);
        l.sistemaOrigem = p.Sistema_Origem__c;
        l.score = p.Risco_Score__c;
        l.farol = p.Farol__c;
        l.exposicao = (p.Exposicao_Financeira__c == null) ? 0 : p.Exposicao_Financeira__c;
        l.exposicaoFmt = moeda(l.exposicao);
        l.estadoCobertura = String.isBlank(p.Estado_Cobertura__c) ? RaizRiskEngine.INSUFICIENTE : p.Estado_Cobertura__c;
        l.fonteCobertura = p.Fonte_Cobertura__c;
        l.exposicaoCompleta = (p.Exposicao_Completa__c != false);
        l.areaRotulo = rotulo(Processo_Critico__c.Area__c, p.Area__c);
        l.criticidadeRotulo = rotulo(Processo_Critico__c.Criticidade__c, p.Criticidade__c);
        l.aptosTexto = (l.pessoasAptas == null) ? '—' : String.valueOf(l.pessoasAptas);
        return l;
    }

    private static List<Fatia> fatias(Map<String,Integer> m, Integer total) {
        List<Fatia> out = new List<Fatia>();
        for (String k : m.keySet()) {
            if (m.get(k) == 0) continue;
            Fatia f = new Fatia();
            f.rotulo = k;
            f.quantidade = m.get(k);
            f.percentual = (total == 0) ? 0
                : (Decimal.valueOf(m.get(k)) / total * 100).setScale(0, System.RoundingMode.HALF_UP);
            out.add(f);
        }
        for (Integer i = 0; i < out.size(); i++) {
            for (Integer j = i + 1; j < out.size(); j++) {
                if (out[j].quantidade > out[i].quantidade) {
                    Fatia t = out[i]; out[i] = out[j]; out[j] = t;
                }
            }
        }
        return out;
    }

    // =====================================================================
    // SIMULADOR — "e se essa pessoa sair amanha?"
    // =====================================================================
    // A frase-ancora do documento da EBL e uma pergunta:
    //   "Se essa pessoa sair amanha, quanto tempo sua operacao leva para
    //    voltar ao normal?"
    // Um painel que so mostra media nao responde isso. Este metodo responde
    // com nome, lista de processos e numero — que e o que trava a reuniao.
    @AuraEnabled(cacheable=true)
    public static ResultadoSimulacao simularSaida(Id contaId, Id usuarioId) {
        ResultadoSimulacao r = new ResultadoSimulacao();
        r.processosParados = 0; r.exposicao = 0; r.horasParaRestabelecer = 0;

        // SOQL nao aceita bind do lado esquerdo de uma comparacao.
        // 'OR :contaId = null' e invalido: o compilador espera um CAMPO ali.
        // Por isso as duas variantes sao escritas por extenso.
        List<Processo_Critico__c> procs;
        if (contaId == null) {
            procs = [
                SELECT Id, Name, Area__c, Criticidade__c, Dono__c, Dono__r.Name,
                       Pessoas_Aptas__c, Ponto_Unico_de_Falha__c, Atualizado__c,
                       Aplicado_no_Sistema__c, Sistema_Origem__c, Risco_Score__c, Farol__c,
                       Exposicao_Financeira__c, Horas_Para_Restabelecer__c,
                       Aptos_Efetivos__c, Estado_Cobertura__c, Fonte_Cobertura__c,
                       Exposicao_Completa__c
                FROM Processo_Critico__c
                WHERE Dono__c = :usuarioId
                WITH USER_MODE
                ORDER BY Risco_Score__c DESC NULLS LAST
                LIMIT 200
            ];
        } else {
            procs = [
                SELECT Id, Name, Area__c, Criticidade__c, Dono__c, Dono__r.Name,
                       Pessoas_Aptas__c, Ponto_Unico_de_Falha__c, Atualizado__c,
                       Aplicado_no_Sistema__c, Sistema_Origem__c, Risco_Score__c, Farol__c,
                       Exposicao_Financeira__c, Horas_Para_Restabelecer__c,
                       Aptos_Efetivos__c, Estado_Cobertura__c, Fonte_Cobertura__c,
                       Exposicao_Completa__c
                FROM Processo_Critico__c
                WHERE Dono__c = :usuarioId AND Conta__c = :contaId
                WITH USER_MODE
                ORDER BY Risco_Score__c DESC NULLS LAST
                LIMIT 200
            ];
        }

        r.pessoa = procs.isEmpty() ? 'Usuario' : procs[0].Dono__r.Name;

        for (Processo_Critico__c p : procs) {
            if (p.Ponto_Unico_de_Falha__c == true) {
                r.processosParados++;
                r.exposicao += (p.Exposicao_Financeira__c == null) ? 0 : p.Exposicao_Financeira__c;
                r.horasParaRestabelecer += (p.Horas_Para_Restabelecer__c == null)
                                           ? 0 : p.Horas_Para_Restabelecer__c.intValue();
                r.processos.add(linha(p));
            }
        }

        r.exposicaoFmt = moeda(r.exposicao);
        Integer dias = (Integer) Math.ceil(r.horasParaRestabelecer / 8.0);
        r.tempoLegivel = (r.horasParaRestabelecer == 0) ? 'sem parada'
                       : (r.horasParaRestabelecer + ' h uteis (~' + dias + ' dias)');

        if (r.processosParados == 0) {
            r.veredito = 'Nenhum processo para. Todo processo sob responsabilidade desta pessoa tem ao menos uma segunda pessoa apta — que e exatamente o resultado que o Metodo RAIZ persegue.';
        } else if (r.processosParados <= 2) {
            r.veredito = 'Exposicao contida, mas existente. ' + r.processosParados +
                         ' processo(s) dependem so desta pessoa. Fase I - Implantacao resolve com registro e segunda pessoa treinada.';
        } else {
            r.veredito = 'Concentracao critica. ' + r.processosParados +
                         ' processos param se esta pessoa sair, com ' + r.exposicaoFmt +
                         ' de exposicao e ' + r.tempoLegivel + ' para restabelecer. Este e o caso classico de Sprint de Sucessao (P5).';
        }
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String,String>> getClientes() {
        List<Map<String,String>> out = new List<Map<String,String>>();
        out.add(new Map<String,String>{ 'label' => 'Todos os clientes', 'value' => '' });
        for (AggregateResult ar : [
            SELECT Conta__c cid, MAX(Conta__r.Name) nome
            FROM Processo_Critico__c
            WHERE Conta__c != null
            WITH USER_MODE
            GROUP BY Conta__c
            ORDER BY MAX(Conta__r.Name)
            LIMIT 50
        ]) {
            out.add(new Map<String,String>{
                'label' => (String) ar.get('nome'),
                'value' => String.valueOf(ar.get('cid'))
            });
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String,String>> getDonos(Id contaId) {
        List<Map<String,String>> out = new List<Map<String,String>>();

        // Mesmo motivo do simularSaida: bind nao pode ficar a esquerda em SOQL.
        List<AggregateResult> linhas;
        if (contaId == null) {
            linhas = [
                SELECT Dono__c uid, MAX(Dono__r.Name) nome, COUNT(Id) qtd
                FROM Processo_Critico__c
                WHERE Dono__c != null
                WITH USER_MODE
                GROUP BY Dono__c
                ORDER BY COUNT(Id) DESC
                LIMIT 50
            ];
        } else {
            linhas = [
                SELECT Dono__c uid, MAX(Dono__r.Name) nome, COUNT(Id) qtd
                FROM Processo_Critico__c
                WHERE Dono__c != null AND Conta__c = :contaId
                WITH USER_MODE
                GROUP BY Dono__c
                ORDER BY COUNT(Id) DESC
                LIMIT 50
            ];
        }

        for (AggregateResult ar : linhas) {
            out.add(new Map<String,String>{
                'label' => (String) ar.get('nome') + '  (' + String.valueOf(ar.get('qtd')) + ' processos)',
                'value' => String.valueOf(ar.get('uid'))
            });
        }
        return out;
    }
}