/**
 * RaizHabilitacaoHandler
 * ---------------------------------------------------------------------------
 * Mantem a contagem de aptos honesta no momento da gravacao:
 *   - Chave_Par__c = Processo|Profissional (campo unico): impede a mesma
 *     pessoa duas vezes no mesmo processo, o que inflaria a cobertura.
 *   - Apto com validade passada vira Vencida ja na gravacao.
 *   - Apto de profissional inativo vira Suspensa.
 *   - Profissional desativado: suas habilitacoes Apto viram Suspensa.
 * O que expira com o passar do tempo (sem ninguem editar) e tratado pelo
 * RaizHabilitacaoVencimentoJob, porque filtro de roll-up nao aceita TODAY().
 */
public with sharing class RaizHabilitacaoHandler {
    public static final String VENCIDA = 'Vencida';
    public static final String SUSPENSA = 'Suspensa';

    /** Desliga o gatilho (uso em teste, para simular o passar do tempo). */
    @TestVisible
    private static Boolean desligado = false;

    public static Boolean ativo() {
        return !desligado;
    }

    public static String chavePar(Id processoId, Id profissionalId) {
        return String.valueOf(processoId) + '|' + String.valueOf(profissionalId);
    }

    /** before insert / before update de Habilitacao__c. */
    public static void antesDeGravar(List<Habilitacao__c> registros) {
        Set<Id> profIds = new Set<Id>();
        for (Habilitacao__c h : registros) {
            if (h.Profissional__c != null) {
                profIds.add(h.Profissional__c);
            }
        }
        Map<Id, Profissional__c> profs = new Map<Id, Profissional__c>(
            [SELECT Id, Ativo__c FROM Profissional__c WHERE Id IN :profIds]
        );
        Date hoje = Date.today();
        for (Habilitacao__c h : registros) {
            if (String.isBlank(h.Status__c)) {
                h.Status__c = RaizRiskEngine.STATUS_APTO;
            }
            h.Chave_Par__c = chavePar(h.Processo__c, h.Profissional__c);
            if (h.Status__c != RaizRiskEngine.STATUS_APTO) {
                continue;
            }
            if (h.Valida_Ate__c != null && h.Valida_Ate__c < hoje) {
                h.Status__c = VENCIDA;
            } else if (profs.containsKey(h.Profissional__c) && profs.get(h.Profissional__c).Ativo__c == false) {
                h.Status__c = SUSPENSA;
            }
        }
    }

    /** after update de Profissional__c. */
    public static void aposAtualizarProfissional(List<Profissional__c> novos, Map<Id, Profissional__c> antigos) {
        Set<Id> desativados = new Set<Id>();
        for (Profissional__c p : novos) {
            if (p.Ativo__c == false && antigos.get(p.Id).Ativo__c == true) {
                desativados.add(p.Id);
            }
        }
        if (desativados.isEmpty()) {
            return;
        }
        List<Habilitacao__c> habs = [
            SELECT Id, Status__c
            FROM Habilitacao__c
            WHERE Profissional__c IN :desativados AND Status__c = :RaizRiskEngine.STATUS_APTO
        ];
        for (Habilitacao__c h : habs) {
            h.Status__c = SUSPENSA;
        }
        update habs;
    }
}
