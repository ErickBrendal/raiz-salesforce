// =====================================================================
// RAIZ Onda 1 — carga de demonstracao IDEMPOTENTE (pode rodar varias vezes)
// Cria 4 profissionais FICTICIOS por empresa e as habilitacoes coerentes com
// o "Pessoas aptas" ja declarado em cada processo. Upsert por chave externa:
// rodar de novo nao duplica nada.
// Divergencia proposital (uma por empresa): no primeiro processo com 2 aptos
// declarados, a habilitacao do substituto esta vencida — o declarado diz 2,
// a evidencia diz 1. E isso que o motor de risco passa a mostrar.
// Nao altera nenhum campo de Processo_Critico__c.
// =====================================================================
Map<Integer, List<String>> nomes = new Map<Integer, List<String>>{
    0 => new List<String>{ 'Helena Prado', 'Otavio Lins', 'Marina Okada', 'Caio Bertolini' },
    1 => new List<String>{ 'Renata Siqueira', 'Joao Paulo Ferraz', 'Bianca Moretti', 'Diego Amaral' },
    2 => new List<String>{ 'Luiza Campello', 'Fabio Teixeira', 'Sofia Navarro', 'Andre Quintela' },
    3 => new List<String>{ 'Paula Rezende', 'Vitor Albuquerque', 'Camila Duarte', 'Rafael Monteiro' },
    4 => new List<String>{ 'Teresa Gouveia', 'Hugo Salles', 'Nina Carvalhal', 'Igor Pacheco' }
};
List<String> cargos = new List<String>{ 'Analista senior', 'Coordenador(a)', 'Analista pleno', 'Assistente' };

List<Processo_Critico__c> procs = [
    SELECT Id, Name, Conta__c, Conta__r.Name, Area__c, Pessoas_Aptas__c
    FROM Processo_Critico__c
    WHERE Conta__c != null
    ORDER BY Conta__r.Name, Name
];
List<Id> contas = new List<Id>();
Map<Id, String> nomeConta = new Map<Id, String>();
for (Processo_Critico__c p : procs) {
    if (!nomeConta.containsKey(p.Conta__c)) { contas.add(p.Conta__c); nomeConta.put(p.Conta__c, p.Conta__r.Name); }
}
if (contas.size() > nomes.size()) {
    System.debug(LoggingLevel.ERROR, 'RAIZ: mais empresas que listas de nomes; so as ' + nomes.size() + ' primeiras recebem carga.');
}

// ---- profissionais
List<Profissional__c> pros = new List<Profissional__c>();
Map<Id, List<String>> chavesPorConta = new Map<Id, List<String>>();
for (Integer c = 0; c < contas.size() && c < nomes.size(); c++) {
    String slug = nomeConta.get(contas[c]).toUpperCase().replaceAll('[^A-Z0-9]+', '-').left(30);
    List<String> chaves = new List<String>();
    for (Integer i = 0; i < 4; i++) {
        String chave = 'RAIZ-PROF-' + slug + '-' + (i + 1);
        chaves.add(chave);
        pros.add(new Profissional__c(
            Name = nomes.get(c)[i], Conta__c = contas[c], Cargo__c = cargos[i],
            Ativo__c = true, Chave_Externa__c = chave));
    }
    chavesPorConta.put(contas[c], chaves);
}
Database.UpsertResult[] urP = Database.upsert(pros, Profissional__c.Chave_Externa__c, true);
Map<String, Id> idPorChave = new Map<String, Id>();
for (Profissional__c p : pros) idPorChave.put(p.Chave_Externa__c, p.Id);

// ---- habilitacoes
Date hoje = Date.today();
List<Habilitacao__c> habs = new List<Habilitacao__c>();
Set<Id> divergiu = new Set<Id>();
List<String> divergentes = new List<String>();
Integer idxArea = 0;
Map<String, Integer> areaIdx = new Map<String, Integer>();
for (Processo_Critico__c p : procs) {
    if (!chavesPorConta.containsKey(p.Conta__c)) continue;
    List<String> ch = chavesPorConta.get(p.Conta__c);
    String area = p.Area__c == null ? '-' : p.Area__c;
    if (!areaIdx.containsKey(area)) areaIdx.put(area, idxArea++);
    // Titular: pessoas 1 e 2 se alternam por area -> concentracao realista.
    Integer titular = Math.mod(areaIdx.get(area), 2);
    if (p.Pessoas_Aptas__c == null) continue; // sem declaracao: continua "Informacao insuficiente"
    Integer n = p.Pessoas_Aptas__c.intValue();
    List<Integer> ordem = new List<Integer>{ titular };
    for (Integer k = 0; k < 4; k++) if (k != titular) ordem.add(k);

    if (n == 0) {
        habs.add(new Habilitacao__c(Processo__c = p.Id, Profissional__c = idPorChave.get(ch[ordem[1]]),
            Status__c = 'Em treinamento', Papel__c = 'Substituto', Ultima_Avaliacao__c = hoje.addDays(-15),
            Evidencia__c = 'Em formacao: acompanhou 2 execucoes (demonstracao).'));
        continue;
    }
    for (Integer k = 0; k < n && k < 4; k++) {
        Boolean vencer = (n == 2 && k == 1 && !divergiu.contains(p.Conta__c));
        habs.add(new Habilitacao__c(
            Processo__c = p.Id, Profissional__c = idPorChave.get(ch[ordem[k]]),
            Status__c = 'Apto', Papel__c = (k == 0 ? 'Titular' : 'Substituto'),
            Ultima_Avaliacao__c = hoje.addMonths(vencer ? -13 : -1),
            Valida_Ate__c = vencer ? hoje.addDays(-20) : hoje.addMonths(6),
            Evidencia__c = vencer ? 'Ultima execucao assistida ha mais de um ano (demonstracao).'
                                  : 'Execucao assistida com checklist (demonstracao).'));
        if (vencer) { divergiu.add(p.Conta__c); divergentes.add(p.Name); }
    }
    if (n == 1 && ordem.size() > 1) {
        habs.add(new Habilitacao__c(Processo__c = p.Id, Profissional__c = idPorChave.get(ch[ordem[1]]),
            Status__c = 'Em treinamento', Papel__c = 'Substituto', Ultima_Avaliacao__c = hoje.addDays(-10),
            Evidencia__c = 'Em formacao (demonstracao).'));
    }
}
for (Habilitacao__c h : habs) h.Chave_Par__c = String.valueOf(h.Processo__c) + '|' + String.valueOf(h.Profissional__c);
Database.upsert(habs, Habilitacao__c.Chave_Par__c, true);

System.debug(LoggingLevel.ERROR, 'RAIZ SEED: empresas=' + chavesPorConta.size() + ' profissionais=' + pros.size()
    + ' habilitacoes=' + habs.size() + ' divergencias_propositais=' + divergentes);
