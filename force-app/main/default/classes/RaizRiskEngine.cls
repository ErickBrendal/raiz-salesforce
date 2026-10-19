/**
 * RaizRiskEngine
 * ---------------------------------------------------------------------------
 * Motor de risco do Metodo RAIZ. Classe pura: sem SOQL, sem DML.
 *
 * As formulas de Processo_Critico__c (Aptos_Efetivos__c, Estado_Cobertura__c,
 * Ponto_Unico_de_Falha__c, Exposicao_Financeira__c, Risco_Score__c, Farol__c)
 * calculam o estado ATUAL de cada processo. Este motor reproduz a mesma regra
 * em Apex para responder perguntas HIPOTETICAS sem gravar nada — por exemplo,
 * "e se esta pessoa faltar?" no simulador. Um teste de contrato
 * (RaizRiskEngineTest.formulaEMotorConcordam) trava as duas implementacoes
 * juntas: se uma mudar sem a outra, o deploy falha.
 *
 * REGRAS
 *   1. Ponto unico = ate 1 pessoa apta (0 ou 1).
 *   2. Exposicao so existe em ponto unico: impacto/hora x horas para restabelecer.
 *   3. Registro vencido nao conta como atualizado (dobra o score).
 *   4. Falta de dado nunca vira verde: "Informacao insuficiente" pesa como
 *      ponto unico no score e nao entra como coberto em lugar nenhum.
 *
 * FONTE DA CONTAGEM
 *   Habilitacoes registradas prevalecem sobre o numero declarado. Sem
 *   habilitacao, usa-se o declarado (Pessoas_Aptas__c). Sem nenhum dos dois,
 *   a contagem e nula: informacao insuficiente.
 */
public with sharing class RaizRiskEngine {
    public static final String SEM_COBERTURA = 'Sem cobertura';
    public static final String PONTO_UNICO = 'Ponto unico';
    public static final String COBERTO = 'Coberto';
    public static final String INSUFICIENTE = 'Informacao insuficiente';

    public static final String FONTE_HABILITACOES = 'Habilitacoes';
    public static final String FONTE_DECLARADO = 'Declarado';
    public static final String FONTE_SEM_DADO = 'Sem dado';

    public static final String STATUS_APTO = 'Apto';

    /** Resultado de uma avaliacao, real ou hipotetica. */
    public class Avaliacao {
        @AuraEnabled
        public Integer aptos;
        @AuraEnabled
        public String estado;
        @AuraEnabled
        public Boolean pontoUnico;
        @AuraEnabled
        public Decimal exposicao;
        @AuraEnabled
        public Boolean exposicaoCompleta;
        @AuraEnabled
        public Integer score;
        @AuraEnabled
        public String farol;
    }

    // ------------------------------------------------------------ contagem
    public static Integer aptosEfetivos(
        Integer habilitacoesRegistradas,
        Integer aptosHabilitados,
        Decimal declarado
    ) {
        if (habilitacoesRegistradas != null && habilitacoesRegistradas > 0) {
            return aptosHabilitados == null ? 0 : aptosHabilitados;
        }
        return declarado == null ? null : declarado.intValue();
    }

    public static String fonte(Integer habilitacoesRegistradas, Decimal declarado) {
        if (habilitacoesRegistradas != null && habilitacoesRegistradas > 0) {
            return FONTE_HABILITACOES;
        }
        return declarado == null ? FONTE_SEM_DADO : FONTE_DECLARADO;
    }

    // -------------------------------------------------------------- estado
    public static String estado(Integer aptos) {
        if (aptos == null) {
            return INSUFICIENTE;
        }
        if (aptos <= 0) {
            return SEM_COBERTURA;
        }
        return aptos == 1 ? PONTO_UNICO : COBERTO;
    }

    /** Regra 1. Sem informacao nao e ponto unico: e um estado proprio. */
    public static Boolean pontoUnico(Integer aptos) {
        return aptos != null && aptos <= 1;
    }

    // ----------------------------------------------------------- exposicao
    /** Regra 2. */
    public static Decimal exposicao(Boolean pontoUnico, Decimal impactoHora, Decimal horas) {
        if (pontoUnico != true) {
            return 0;
        }
        return (impactoHora == null ? 0 : impactoHora) * (horas == null ? 0 : horas);
    }

    /** Falso quando ha ponto unico mas falta insumo: o valor esta subestimado. */
    public static Boolean exposicaoCompleta(Boolean pontoUnico, Decimal impactoHora, Decimal horas) {
        return pontoUnico != true || (impactoHora != null && horas != null);
    }

    // --------------------------------------------------------------- score
    private static final Map<String, Integer> PESO = new Map<String, Integer>{
        'Critico' => 4,
        'Alto' => 3,
        'Medio' => 2
    };

    public static Integer pesoCriticidade(String criticidade) {
        return (criticidade != null && PESO.containsKey(criticidade)) ? PESO.get(criticidade) : 1;
    }

    /** Regra 4: insuficiente pesa 3, igual a ponto unico. */
    public static Integer fatorDependencia(Integer aptos) {
        if (estado(aptos) != COBERTO) {
            return 3;
        }
        return aptos == 2 ? 2 : 1;
    }

    /** Regra 3: so e atualizado se Registrado, com revisao e dentro da validade. */
    public static Boolean atualizado(String statusRegistro, Date ultimaRevisao, Decimal validadeMeses, Date hoje) {
        if (statusRegistro != 'Registrado' || ultimaRevisao == null) {
            return false;
        }
        Integer meses = (validadeMeses == null) ? 6 : validadeMeses.intValue();
        return ultimaRevisao.addMonths(meses) >= hoje;
    }

    public static Integer score(String criticidade, Integer aptos, Boolean atualizado) {
        return pesoCriticidade(criticidade) * fatorDependencia(aptos) * (atualizado == true ? 1 : 2);
    }

    /** Espelha Farol__c (CASE sobre os 11 scores possiveis: 1,2,3,4,6,8,9,12,16,18,24). */
    public static String farol(Integer score) {
        if (score == null) {
            return 'Baixo';
        }
        if (score >= 16) {
            return 'Critico';
        }
        if (score >= 9) {
            return 'Alto';
        }
        return score >= 5 ? 'Medio' : 'Baixo';
    }

    // ------------------------------------------------------- habilitacao
    /** Apto, profissional ativo e dentro da validade (em branco = sem prazo). */
    public static Boolean vigente(String status, Boolean profissionalAtivo, Date validaAte, Date hoje) {
        return status == STATUS_APTO && profissionalAtivo != false && (validaAte == null || validaAte >= hoje);
    }

    // ------------------------------------------------------------ avaliar
    /**
     * Avalia um processo com uma contagem de aptos informada (real ou
     * hipotetica). 'atualizado' vem do proprio registro (Atualizado__c).
     */
    public static Avaliacao avaliar(Processo_Critico__c p, Integer aptos) {
        Avaliacao a = new Avaliacao();
        a.aptos = aptos;
        a.estado = estado(aptos);
        a.pontoUnico = pontoUnico(aptos);
        a.exposicao = exposicao(a.pontoUnico, p.Impacto_Hora__c, p.Horas_Para_Restabelecer__c);
        a.exposicaoCompleta = exposicaoCompleta(a.pontoUnico, p.Impacto_Hora__c, p.Horas_Para_Restabelecer__c);
        a.score = score(p.Criticidade__c, aptos, p.Atualizado__c == true);
        a.farol = farol(a.score);
        return a;
    }
}
