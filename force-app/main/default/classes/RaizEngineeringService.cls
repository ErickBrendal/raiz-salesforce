/**
 * RaizEngineeringService — dados do painel RAIZ Engineering Intelligence (Onda 8).
 * ---------------------------------------------------------------------------
 * So LEITURA. Cada indicador tem a regra escrita em `regras` e a tela mostra
 * essa regra ao lado do numero. Funcionalidade e componente sao contados
 * separadamente; "verificado" vem do verificador (Estado_Validacao__c), nunca
 * do que o item declara. Testes vem da ULTIMA implantacao registrada pelo sf CLI.
 *
 * SEGURANCA: with sharing; consultas WITH USER_MODE.
 */
public with sharing class RaizEngineeringService {
    public class Indicador {
        @AuraEnabled
        public String chave;
        @AuraEnabled
        public String rotulo;
        @AuraEnabled
        public String valor;
        @AuraEnabled
        public String regra;
        @AuraEnabled
        public String tom; // bom | atencao | critico | neutro
        public Indicador(String chave, String rotulo, String valor, String regra, String tom) {
            this.chave = chave;
            this.rotulo = rotulo;
            this.valor = valor;
            this.regra = regra;
            this.tom = tom;
        }
    }

    public class Item {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String nome;
        @AuraEnabled
        public String nivel;
        @AuraEnabled
        public String modulo;
        @AuraEnabled
        public String tipo;
        @AuraEnabled
        public String api;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String estado;
        @AuraEnabled
        public String resultado;
        @AuraEnabled
        public DateTime verificadoEm;
        @AuraEnabled
        public String onda;
        @AuraEnabled
        public String adr;
        @AuraEnabled
        public String teste;
        @AuraEnabled
        public String objetivo;
        @AuraEnabled
        public String problema;
        @AuraEnabled
        public String tecnologia;
        @AuraEnabled
        public String limitacoes;
        @AuraEnabled
        public String proxima;
        @AuraEnabled
        public String usoIa;
        @AuraEnabled
        public String humano;
        @AuraEnabled
        public Boolean portfolio = false;
        @AuraEnabled
        public Id funcionalidadeId;
        @AuraEnabled
        public Integer evidenciasAprovadas = 0;
        @AuraEnabled
        public Integer componentes = 0;
        @AuraEnabled
        public Integer componentesVerificados = 0;
    }

    public class Implantacao {
        @AuraEnabled
        public String deployId;
        @AuraEnabled
        public String onda;
        @AuraEnabled
        public DateTime quando;
        @AuraEnabled
        public Integer componentes;
        @AuraEnabled
        public Integer testes;
        @AuraEnabled
        public Integer aprovados;
        @AuraEnabled
        public String resultado;
    }

    public class Log {
        @AuraEnabled
        public String nome;
        @AuraEnabled
        public String tipo;
        @AuraEnabled
        public String etapa;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer execucoes;
        @AuraEnabled
        public DateTime quando;
        @AuraEnabled
        public String mensagem;
    }

    public class Painel {
        @AuraEnabled
        public List<Indicador> indicadores = new List<Indicador>();
        @AuraEnabled
        public List<Item> funcionalidades = new List<Item>();
        @AuraEnabled
        public List<Item> componentes = new List<Item>();
        @AuraEnabled
        public List<Implantacao> implantacoes = new List<Implantacao>();
        @AuraEnabled
        public List<Log> logs = new List<Log>();
        @AuraEnabled
        public Map<String, Integer> logsPorStatus = new Map<String, Integer>();
        @AuraEnabled
        public List<String> pendencias = new List<String>();
        @AuraEnabled
        public DateTime ultimaVerificacao;
        @AuraEnabled
        public String origemVerificacao;
        @AuraEnabled
        public Boolean semPermissao = false;
        @AuraEnabled
        public String erro;
    }

    @AuraEnabled
    public static Painel getPainel() {
        Painel p = new Painel();
        try {
            montar(p);
        } catch (Exception e) {
            String m = e.getMessage() == null ? '' : e.getMessage();
            p.semPermissao = m.containsIgnoreCase('access') || m.containsIgnoreCase('No such column') || m.containsIgnoreCase('not supported');
            p.erro = p.semPermissao ? 'Sem acesso ao inventário de engenharia. Peça o permission set EBL_RAIZ_Cockpit.' : m;
        }
        return p;
    }

    private static void montar(Painel p) {
        Map<Id, Item> porId = new Map<Id, Item>();
        for (RAIZ_Engineering_Status__c s : [
            SELECT
                Id,
                Name,
                Nivel__c,
                Modulo__c,
                Tipo_Componente__c,
                API_Name__c,
                Status_Implementacao__c,
                Estado_Validacao__c,
                Resultado_Verificacao__c,
                Ultima_Verificacao__c,
                Origem_Verificacao__c,
                Onda__c,
                ADR__c,
                Teste_Associado__c,
                Objetivo_Funcional__c,
                Problema_Negocio__c,
                Tecnologia__c,
                Limitacoes__c,
                Proxima_Evolucao__c,
                Uso_IA__c,
                Contribuicao_Humana__c,
                Portfolio__c,
                Funcionalidade__c
            FROM RAIZ_Engineering_Status__c
            WITH USER_MODE
            ORDER BY Onda__c, Name
            LIMIT 2000
        ]) {
            Item i = new Item();
            i.id = s.Id;
            i.nome = s.Name;
            i.nivel = s.Nivel__c;
            i.modulo = RaizCockpitService.rotulo(RAIZ_Engineering_Status__c.Modulo__c, s.Modulo__c);
            i.tipo = RaizCockpitService.rotulo(RAIZ_Engineering_Status__c.Tipo_Componente__c, s.Tipo_Componente__c);
            i.api = s.API_Name__c;
            i.status = s.Status_Implementacao__c;
            i.estado = s.Estado_Validacao__c == null ? 'Declarado' : s.Estado_Validacao__c;
            i.resultado = s.Resultado_Verificacao__c;
            i.verificadoEm = s.Ultima_Verificacao__c;
            i.onda = s.Onda__c;
            i.adr = s.ADR__c;
            i.teste = s.Teste_Associado__c;
            i.objetivo = s.Objetivo_Funcional__c;
            i.problema = s.Problema_Negocio__c;
            i.tecnologia = s.Tecnologia__c;
            i.limitacoes = s.Limitacoes__c;
            i.proxima = s.Proxima_Evolucao__c;
            i.usoIa = s.Uso_IA__c;
            i.humano = s.Contribuicao_Humana__c;
            i.portfolio = s.Portfolio__c == true;
            i.funcionalidadeId = s.Funcionalidade__c;
            porId.put(i.id, i);
            if (s.Nivel__c == 'Funcionalidade') p.funcionalidades.add(i);
            else p.componentes.add(i);
            if (s.Ultima_Verificacao__c != null && (p.ultimaVerificacao == null || s.Ultima_Verificacao__c > p.ultimaVerificacao)) {
                p.ultimaVerificacao = s.Ultima_Verificacao__c;
                p.origemVerificacao = s.Origem_Verificacao__c;
            }
        }
        if (!porId.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Item__c it, COUNT(Id) n
                FROM RAIZ_Evidencia__c
                WHERE Resultado__c = 'Aprovado' AND Item__c IN :porId.keySet()
                WITH USER_MODE
                GROUP BY Item__c
            ]) {
                porId.get((Id) ar.get('it')).evidenciasAprovadas = (Integer) ar.get('n');
            }
        }
        for (Item c : p.componentes) {
            Item f = porId.get(c.funcionalidadeId);
            if (f == null) continue;
            f.componentes++;
            if (c.estado == 'Verificado') f.componentesVerificados++;
        }

        Integer fImpl = 0, fVal = 0, fPlan = 0;
        for (Item f : p.funcionalidades) {
            if (f.status == 'Implementado') fImpl++;
            if (f.status == 'Planejado') fPlan++;
            if (f.estado == 'Verificado') fVal++;
            if (f.status != 'Implementado') p.pendencias.add(f.nome + ': ' + (f.status == null ? 'sem status' : f.status.toLowerCase()) + '.');
        }
        Integer cVer = 0, cFal = 0, cNv = 0, cSem = 0, cDecl = 0;
        for (Item c : p.componentes) {
            if (c.estado == 'Verificado') cVer++;
            else if (c.estado == 'Falhou') {
                cFal++;
                p.pendencias.add(c.nome + ' (' + c.api + '): ' + (c.resultado == null ? 'falhou na verificação' : c.resultado));
            } else if (c.estado == 'Nao verificavel') cNv++;
            else cDecl++;
            if (c.evidenciasAprovadas == 0) cSem++;
        }

        for (RAIZ_Implantacao__c d : [
            SELECT Deploy_Id__c, Onda__c, Executado_Em__c, Componentes__c, Testes_Executados__c, Testes_Aprovados__c, Resultado__c
            FROM RAIZ_Implantacao__c
            WITH USER_MODE
            ORDER BY Executado_Em__c DESC NULLS LAST
            LIMIT 50
        ]) {
            Implantacao x = new Implantacao();
            x.deployId = d.Deploy_Id__c;
            x.onda = d.Onda__c;
            x.quando = d.Executado_Em__c;
            x.componentes = d.Componentes__c == null ? null : d.Componentes__c.intValue();
            x.testes = d.Testes_Executados__c == null ? null : d.Testes_Executados__c.intValue();
            x.aprovados = d.Testes_Aprovados__c == null ? null : d.Testes_Aprovados__c.intValue();
            x.resultado = d.Resultado__c;
            p.implantacoes.add(x);
        }
        Implantacao ult = null;
        for (Implantacao x : p.implantacoes) {
            if (x.resultado == 'Sucesso') {
                ult = x;
                break;
            }
        }

        for (RAIZ_Log_Execucao__c l : [
            SELECT Name, Tipo__c, Etapa__c, Status__c, Execucoes__c, Executado_Em__c, Mensagem__c
            FROM RAIZ_Log_Execucao__c
            WITH USER_MODE
            ORDER BY Executado_Em__c DESC
            LIMIT 15
        ]) {
            Log x = new Log();
            x.nome = l.Name;
            x.tipo = RaizCockpitService.rotulo(RAIZ_Log_Execucao__c.Tipo__c, l.Tipo__c);
            x.etapa = l.Etapa__c;
            x.status = l.Status__c;
            x.execucoes = l.Execucoes__c == null ? 1 : l.Execucoes__c.intValue();
            x.quando = l.Executado_Em__c;
            x.mensagem = l.Mensagem__c;
            p.logs.add(x);
        }
        for (AggregateResult ar : [
            SELECT Status__c s, COUNT(Id) n
            FROM RAIZ_Log_Execucao__c
            WHERE Tipo__c = 'Automacao'
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            p.logsPorStatus.put((String) ar.get('s'), (Integer) ar.get('n'));
        }

        Integer integ = 0, integOk = 0;
        for (Item c : p.componentes) {
            if (c.modulo == RaizCockpitService.rotulo(RAIZ_Engineering_Status__c.Modulo__c, 'Integracao')) {
                integ++;
                if (c.estado == 'Verificado') integOk++;
            }
        }

        Integer nf = p.funcionalidades.size();
        Integer nc = p.componentes.size();
        p.indicadores.add(new Indicador('func-impl', 'Funcionalidades implementadas', fImpl + ' de ' + nf,
            'Itens de nível Funcionalidade com status declarado "Implementado". Declarado pelo autor.', fImpl == nf ? 'bom' : 'neutro'));
        p.indicadores.add(new Indicador('func-val', 'Funcionalidades validadas', fVal + ' de ' + fImpl,
            'Funcionalidades em que TODOS os componentes foram verificados na org pela última verificação.', fVal == fImpl && fImpl > 0 ? 'bom' : 'atencao'));
        p.indicadores.add(new Indicador('comp-ver', 'Componentes verificados', cVer + ' de ' + nc,
            'Componentes com estado "Verificado": o verificador encontrou o metadado na org (e o teste associado passou, quando há).', cVer == nc ? 'bom' : 'atencao'));
        p.indicadores.add(new Indicador('comp-falha', 'Componentes com falha', String.valueOf(cFal),
            'Metadado não encontrado, inativo ou teste associado reprovado na última execução.', cFal > 0 ? 'critico' : 'bom'));
        p.indicadores.add(new Indicador('comp-nv', 'Não verificáveis', String.valueOf(cNv + cDecl),
            'Sem como confirmar agora (ex.: LWC sem evidência recente do sf CLI) ou ainda não verificados (Declarado).', cNv + cDecl > 0 ? 'atencao' : 'bom'));
        p.indicadores.add(new Indicador('comp-sem-ev', 'Sem evidência aprovada', String.valueOf(cSem),
            'Componentes sem nenhuma evidência com resultado Aprovado.', cSem > 0 ? 'atencao' : 'bom'));
        p.indicadores.add(new Indicador('testes', 'Testes na última implantação',
            ult == null || ult.testes == null ? 'sem registro' : ult.aprovados + ' de ' + ult.testes,
            'Métodos aprovados/executados no deploy mais recente com sucesso, registrado a partir do sf CLI. Não é contagem manual.',
            ult == null ? 'neutro' : (ult.aprovados == ult.testes ? 'bom' : 'critico')));
        p.indicadores.add(new Indicador('automacao', 'Execuções da automação',
            String.valueOf((p.logsPorStatus.get('Sucesso') == null ? 0 : p.logsPorStatus.get('Sucesso'))) + ' ok · ' +
            String.valueOf((p.logsPorStatus.get('Bloqueado') == null ? 0 : p.logsPorStatus.get('Bloqueado'))) + ' bloqueadas · ' +
            String.valueOf((p.logsPorStatus.get('Erro') == null ? 0 : p.logsPorStatus.get('Erro'))) + ' erros',
            'Registros do log de execução de tipo Automação, por resultado. Bloqueado é regra funcionando, não erro.', 'neutro'));
        p.indicadores.add(new Indicador('integracao', 'Integrações verificadas', integOk + ' de ' + integ,
            'Componentes do módulo Integração com estado Verificado.', integ == 0 ? 'neutro' : (integOk == integ ? 'bom' : 'atencao')));
    }
}
