/**
 * RaizJourneyService — RAIZ Guided Journey (Onda 6): cadastro assistido de conhecimento.
 * ---------------------------------------------------------------------------
 * Backend do LWC raizGuidedJourney (decisao D1: LWC, nao Screen Flow).
 *
 * O QUE ESTA CLASSE FAZ
 *   getContexto()                  processos, opcoes e revisores para as telas
 *   getSituacao(processoId)        o processo ja tem documento? (retomar rascunho
 *                                  ou bloquear quando ja esta em revisao/publicado)
 *   validar(dadosJson, encaminhar) bloqueios por tela + avisos de governanca
 *   salvar(dadosJson, encaminhar)  grava SO aqui (tela 7, clique explicito)
 *
 * O QUE ELA NAO FAZ (de proposito)
 *   - Nao repete as regras do documento: o encaminhamento usa
 *     RaizKnowledgeService.moverDocumento e as faltas de governanca vem de
 *     RaizGovernancaService.avaliarSubmissao.
 *   - Nao bloqueia o encaminhamento por falta de conteudo (decisao D6): mostra
 *     como aviso; quem barra e a governanca.
 *
 * IDEMPOTENCIA: um documento por processo no fluxo. Salvar de novo o mesmo
 * processo atualiza o rascunho existente em vez de criar outro.
 *
 * MAPEAMENTO PARA O DOCUMENTO FUNCIONAL (Business_Rule__c, ADR-005):
 *   resumo -> Proposito_Documento__c        etapas -> Descricao_Demanda__c
 *   resultadoEsperado -> Criterios_Aceite__c excecoes -> Cenarios_Teste__c
 *   categoria -> Domain__c   criticidade -> Criticality__c
 *   dataReferencia -> Last_Review_Date__c   palavrasChave -> Keywords__c
 *
 * SEGURANCA: with sharing; leituras WITH USER_MODE; escritas AccessLevel.USER_MODE.
 */
public with sharing class RaizJourneyService {
    // ================================================================ DTOs
    public class Opcao {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        public Opcao(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ProcessoResumo {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String nome;
        @AuraEnabled
        public String area;
        @AuraEnabled
        public String responsavel;
        @AuraEnabled
        public String criticidade;
        @AuraEnabled
        public String criticidadeDocumento;
        @AuraEnabled
        public String estadoCobertura;
        @AuraEnabled
        public String situacaoDocumento;
    }

    public class Contexto {
        @AuraEnabled
        public Id usuarioId;
        @AuraEnabled
        public String usuarioNome;
        @AuraEnabled
        public List<ProcessoResumo> processos = new List<ProcessoResumo>();
        @AuraEnabled
        public List<Opcao> tipos = new List<Opcao>();
        @AuraEnabled
        public List<Opcao> categorias = new List<Opcao>();
        @AuraEnabled
        public List<Opcao> criticidades = new List<Opcao>();
        @AuraEnabled
        public List<RaizGovernancaService.Revisor> revisores = new List<RaizGovernancaService.Revisor>();
    }

    public class Dados {
        @AuraEnabled
        public Id documentoId;
        @AuraEnabled
        public Id processoId;
        @AuraEnabled
        public String titulo;
        @AuraEnabled
        public String tipo;
        @AuraEnabled
        public String categoria;
        @AuraEnabled
        public String resumo;
        @AuraEnabled
        public String palavrasChave;
        @AuraEnabled
        public Id revisorId;
        @AuraEnabled
        public Date dataReferencia;
        @AuraEnabled
        public Date proximaRevisao;
        @AuraEnabled
        public Date prazoRevisao;
        @AuraEnabled
        public String criticidade;
        @AuraEnabled
        public String preRequisitos;
        @AuraEnabled
        public String etapas;
        @AuraEnabled
        public String resultadoEsperado;
        @AuraEnabled
        public String excecoes;
        @AuraEnabled
        public String contingencia;
        @AuraEnabled
        public String referencias;
    }

    /** NOVO | RASCUNHO | EM_REVISAO | APROVADO | PUBLICADO */
    public class Situacao {
        @AuraEnabled
        public String estado;
        @AuraEnabled
        public String mensagem;
        @AuraEnabled
        public Boolean podeContinuar = false;
        @AuraEnabled
        public Dados dados;
    }

    public class Item {
        @AuraEnabled
        public Integer etapa;
        @AuraEnabled
        public String mensagem;
        public Item(Integer etapa, String mensagem) {
            this.etapa = etapa;
            this.mensagem = mensagem;
        }
    }

    public class Revisao {
        @AuraEnabled
        public List<Item> bloqueios = new List<Item>();
        @AuraEnabled
        public List<String> avisos = new List<String>();
    }

    public class Resultado {
        @AuraEnabled
        public Id documentoId;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean criado = false;
        @AuraEnabled
        public Boolean encaminhado = false;
        @AuraEnabled
        public RaizGovernancaService.Cartao cartao;
        @AuraEnabled
        public List<String> avisos = new List<String>();
        @AuraEnabled
        public List<String> proximosPassos = new List<String>();
    }

    private static final Map<String, String> ESTADO_POR_STATUS = new Map<String, String>{
        'Draft' => 'RASCUNHO',
        'Em Analise' => 'EM_REVISAO',
        'Aprovada' => 'APROVADO',
        'Publicada' => 'PUBLICADO'
    };
    private static final Map<String, String> CRITICIDADE_DOC = new Map<String, String>{
        'Critico' => 'Critica',
        'Alto' => 'Alta',
        'Medio' => 'Media',
        'Baixo' => 'Baixa'
    };

    // ============================================================ leitura
    @AuraEnabled
    public static Contexto getContexto() {
        try {
            Contexto c = new Contexto();
            c.usuarioId = UserInfo.getUserId();
            c.usuarioNome = UserInfo.getName();
            c.tipos = opcoes(Business_Rule__c.Tipo_Documento__c);
            c.categorias = opcoes(Business_Rule__c.Domain__c);
            c.criticidades = opcoes(Business_Rule__c.Criticality__c);
            c.revisores = RaizGovernancaService.revisoresElegiveis(c.usuarioId);

            List<Processo_Critico__c> ps = [
                SELECT Id, Name, Area__c, Criticidade__c, Estado_Cobertura__c, Dono__r.Name
                FROM Processo_Critico__c
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1000
            ];
            Map<Id, String> statusDoc = new Map<Id, String>();
            Set<Id> idsProcessos = new Map<Id, Processo_Critico__c>(ps).keySet();
            for (Business_Rule__c d : [
                SELECT Processo_Critico__c, Status__c
                FROM Business_Rule__c
                WHERE Processo_Critico__c IN :idsProcessos
                    AND Status__c IN :RaizKnowledgeService.FLUXO
                WITH USER_MODE
            ]) {
                statusDoc.put(d.Processo_Critico__c, d.Status__c);
            }
            for (Processo_Critico__c p : ps) {
                ProcessoResumo r = new ProcessoResumo();
                r.id = p.Id;
                r.nome = p.Name;
                r.area = RaizCockpitService.rotulo(Processo_Critico__c.Area__c, p.Area__c);
                r.responsavel = p.Dono__r == null ? null : p.Dono__r.Name;
                r.criticidade = RaizCockpitService.rotulo(Processo_Critico__c.Criticidade__c, p.Criticidade__c);
                r.criticidadeDocumento = CRITICIDADE_DOC.get(p.Criticidade__c);
                r.estadoCobertura = p.Estado_Cobertura__c;
                String st = statusDoc.get(p.Id);
                r.situacaoDocumento = st == null ? 'Sem documento' : rotuloStatus(st);
                c.processos.add(r);
            }
            return c;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    @AuraEnabled
    public static Situacao getSituacao(Id processoId) {
        if (processoId == null) throw aura('Escolha um processo.');
        try {
            Situacao s = new Situacao();
            Integer acesso = [SELECT COUNT() FROM Processo_Critico__c WHERE Id = :processoId WITH USER_MODE];
            if (acesso == 0) throw aura('Processo não encontrado ou sem acesso.');
            Business_Rule__c d = documentoDoProcesso(processoId);
            if (d == null) {
                s.estado = 'NOVO';
                s.podeContinuar = true;
                s.mensagem = 'Este processo ainda não tem documento. Você vai criar o primeiro.';
                return s;
            }
            s.estado = ESTADO_POR_STATUS.get(d.Status__c);
            if (d.Status__c == 'Draft') {
                s.podeContinuar = true;
                s.dados = paraDados(d);
                s.mensagem = 'Já existe um rascunho deste processo. Os dados foram carregados para você continuar de onde parou.';
            } else if (d.Status__c == 'Publicada') {
                s.mensagem = 'O documento deste processo já está publicado. Para alterá-lo, abra o documento; o cadastro guiado não cria uma segunda versão.';
            } else {
                s.mensagem = 'O documento deste processo está "' + rotuloStatus(d.Status__c) + '". Acompanhe pelo Knowledge Hub.';
            }
            s.dados = s.dados == null ? new Dados() : s.dados;
            s.dados.documentoId = d.Id;
            return s;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    @AuraEnabled
    public static Revisao validar(String dadosJson, Boolean encaminhar) {
        try {
            return revisar(ler(dadosJson), encaminhar == true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
    }

    // ============================================================ escrita
    @AuraEnabled
    public static Resultado salvar(String dadosJson, Boolean encaminhar) {
        Dados x = ler(dadosJson);
        Boolean enviar = encaminhar == true;
        Revisao rv;
        try {
            rv = revisar(x, enviar);
        } catch (Exception e) {
            throw erroAmigavel(e);
        }
        if (!rv.bloqueios.isEmpty()) {
            List<String> ms = new List<String>();
            for (Item i : rv.bloqueios) ms.add(i.mensagem);
            throw aura('Corrija antes de salvar: ' + String.join(ms, ' '));
        }
        Resultado r = new Resultado();
        try {
            Business_Rule__c existente = documentoDoProcesso(x.processoId);
            List<Project__c> proj = [
                SELECT Id
                FROM Project__c
                WHERE Name = :RaizKnowledgeService.PROJETO_RAIZ
                WITH USER_MODE
                LIMIT 1
            ];
            if (proj.isEmpty()) {
                throw aura('Projeto "' + RaizKnowledgeService.PROJETO_RAIZ + '" não encontrado. Rode a carga da Onda 5.');
            }
            Business_Rule__c d = paraRegistro(x);
            if (existente == null) {
                d.Status__c = 'Draft';
                d.Project__c = proj[0].Id;
                d.Business_Owner__c = UserInfo.getUserId();
                Database.insert(d, AccessLevel.USER_MODE);
                r.criado = true;
            } else {
                d.Id = existente.Id;
                Database.update(d, AccessLevel.USER_MODE);
            }
            r.documentoId = d.Id;
            r.status = 'Draft';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw erroAmigavel(e);
        }

        if (enviar) {
            try {
                RaizKnowledgeService.moverDocumento(r.documentoId, 1);
                r.status = 'Em Analise';
                r.encaminhado = true;
            } catch (Exception e) {
                r.avisos.add('O documento foi salvo como rascunho, mas não foi encaminhado: ' + e.getMessage());
            }
        }
        r.avisos.addAll(rv.avisos);
        r.cartao = RaizGovernancaService.sincronizarCartao(r.documentoId);
        if (r.cartao.aviso != null) r.avisos.add(r.cartao.aviso);

        if (r.encaminhado) {
            r.proximosPassos.add('O revisor avalia o documento no Knowledge Hub (coluna "Em revisão").');
            r.proximosPassos.add('Aprovar e publicar exigem a permissão de aprovação: você não aprova o próprio documento.');
            r.proximosPassos.add('Ao publicar, o processo passa a "Registrado" e a atualidade do acervo sobe no Cockpit.');
        } else {
            r.proximosPassos.add('O rascunho fica na coluna "Em elaboração" do Knowledge Hub.');
            r.proximosPassos.add('Para continuar, abra o cadastro guiado e escolha o mesmo processo: os dados são carregados.');
        }
        r.proximosPassos.add('Anexos: abra o documento e use a lista "Arquivos".');
        return r;
    }

    // ============================================================ regras
    @TestVisible
    private static Revisao revisar(Dados x, Boolean encaminhar) {
        Revisao rv = new Revisao();
        Id autor = UserInfo.getUserId();

        // Tela 2 — processo
        if (x.processoId == null) {
            rv.bloqueios.add(new Item(2, 'Escolha o processo crítico.'));
        } else {
            Integer acesso = [SELECT COUNT() FROM Processo_Critico__c WHERE Id = :x.processoId WITH USER_MODE];
            if (acesso == 0) {
                rv.bloqueios.add(new Item(2, 'Processo não encontrado ou sem acesso.'));
            } else {
                Business_Rule__c d = documentoDoProcesso(x.processoId);
                if (d != null && d.Status__c != 'Draft') {
                    rv.bloqueios.add(
                        new Item(2, 'O documento deste processo já está "' + rotuloStatus(d.Status__c) + '"; acompanhe pelo Knowledge Hub.')
                    );
                } else if (x.documentoId != null && (d == null || d.Id != x.documentoId)) {
                    rv.bloqueios.add(new Item(2, 'O rascunho informado não pertence a este processo. Escolha o processo de novo.'));
                }
            }
        }
        // Tela 3 — classificacao
        if (String.isBlank(x.titulo)) {
            rv.bloqueios.add(new Item(3, 'Informe o título.'));
        } else if (x.titulo.trim().length() > 120) {
            rv.bloqueios.add(new Item(3, 'O título tem mais de 120 caracteres.'));
        }
        if (!valido(Business_Rule__c.Tipo_Documento__c, x.tipo)) rv.bloqueios.add(new Item(3, 'Escolha o tipo de documento.'));
        if (!valido(Business_Rule__c.Domain__c, x.categoria)) rv.bloqueios.add(new Item(3, 'Escolha a categoria.'));
        if (x.palavrasChave != null && x.palavrasChave.length() > 255) {
            rv.bloqueios.add(new Item(3, 'As palavras-chave passam de 255 caracteres.'));
        }
        // Tela 4 — responsabilidade e revisao
        if (!valido(Business_Rule__c.Criticality__c, x.criticidade)) rv.bloqueios.add(new Item(4, 'Escolha a criticidade do documento.'));
        if (x.revisorId != null) {
            if (x.revisorId == autor) {
                rv.bloqueios.add(new Item(4, 'Você não pode revisar o próprio documento.'));
            } else if (!RaizGovernancaService.revisorElegivel(x.revisorId, autor)) {
                rv.bloqueios.add(new Item(4, 'O revisor escolhido não tem a permissão de aprovação.'));
            }
        }
        Date hoje = Date.today();
        if (x.dataReferencia != null && x.dataReferencia > hoje) {
            rv.bloqueios.add(new Item(4, 'A data de referência não pode estar no futuro.'));
        }
        if (x.proximaRevisao != null && x.proximaRevisao <= hoje) {
            rv.bloqueios.add(new Item(4, 'A próxima revisão precisa ser uma data futura.'));
        }
        if (x.proximaRevisao != null && x.dataReferencia != null && x.proximaRevisao <= x.dataReferencia) {
            rv.bloqueios.add(new Item(4, 'A próxima revisão precisa ser depois da data de referência.'));
        }
        if (x.prazoRevisao != null && x.prazoRevisao < hoje) {
            rv.bloqueios.add(new Item(4, 'O prazo da revisão já passou.'));
        }

        // Avisos de governanca (nao bloqueiam: decisao D6)
        RaizGovernancaService.Avaliacao a = RaizGovernancaService.avaliarSubmissao(paraRegistro(x));
        if (encaminhar && !a.faltas.isEmpty()) {
            rv.avisos.add('Recomendado antes de encaminhar: ' + String.join(a.faltas, ', ') + '.');
        }
        rv.avisos.addAll(a.avisos);
        return rv;
    }

    // =========================================================== apoio
    private static Dados ler(String dadosJson) {
        if (String.isBlank(dadosJson)) throw aura('Nenhum dado recebido.');
        try {
            return (Dados) JSON.deserialize(dadosJson, Dados.class);
        } catch (Exception e) {
            throw aura('Dados do cadastro em formato inválido. Recarregue a página e tente de novo.');
        }
    }

    private static Business_Rule__c documentoDoProcesso(Id processoId) {
        if (processoId == null) return null;
        List<Business_Rule__c> ds = [
            SELECT
                Id,
                Status__c,
                Title__c,
                Tipo_Documento__c,
                Domain__c,
                Proposito_Documento__c,
                Keywords__c,
                Revisor__c,
                Last_Review_Date__c,
                Proxima_Revisao__c,
                Prazo_Revisao__c,
                Criticality__c,
                Pre_Requisitos__c,
                Descricao_Demanda__c,
                Criterios_Aceite__c,
                Cenarios_Teste__c,
                Plano_Contingencia__c,
                Referencias__c,
                Processo_Critico__c
            FROM Business_Rule__c
            WHERE Processo_Critico__c = :processoId AND Status__c IN :RaizKnowledgeService.FLUXO
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return ds.isEmpty() ? null : ds[0];
    }

    private static Dados paraDados(Business_Rule__c d) {
        Dados x = new Dados();
        x.documentoId = d.Id;
        x.processoId = d.Processo_Critico__c;
        x.titulo = d.Title__c;
        x.tipo = d.Tipo_Documento__c;
        x.categoria = d.Domain__c;
        x.resumo = d.Proposito_Documento__c;
        x.palavrasChave = d.Keywords__c;
        x.revisorId = d.Revisor__c;
        x.dataReferencia = d.Last_Review_Date__c;
        x.proximaRevisao = d.Proxima_Revisao__c;
        x.prazoRevisao = d.Prazo_Revisao__c;
        x.criticidade = d.Criticality__c;
        x.preRequisitos = d.Pre_Requisitos__c;
        x.etapas = d.Descricao_Demanda__c;
        x.resultadoEsperado = d.Criterios_Aceite__c;
        x.excecoes = d.Cenarios_Teste__c;
        x.contingencia = d.Plano_Contingencia__c;
        x.referencias = d.Referencias__c;
        return x;
    }

    private static Business_Rule__c paraRegistro(Dados x) {
        return new Business_Rule__c(
            Processo_Critico__c = x.processoId,
            Title__c = x.titulo == null ? null : x.titulo.trim(),
            Tipo_Documento__c = x.tipo,
            Domain__c = x.categoria,
            Proposito_Documento__c = x.resumo,
            Keywords__c = x.palavrasChave,
            Revisor__c = x.revisorId,
            Last_Review_Date__c = x.dataReferencia,
            Proxima_Revisao__c = x.proximaRevisao,
            Prazo_Revisao__c = x.prazoRevisao,
            Criticality__c = x.criticidade,
            Pre_Requisitos__c = x.preRequisitos,
            Descricao_Demanda__c = x.etapas,
            Criterios_Aceite__c = x.resultadoEsperado,
            Cenarios_Teste__c = x.excecoes,
            Plano_Contingencia__c = x.contingencia,
            Referencias__c = x.referencias
        );
    }

    private static List<Opcao> opcoes(Schema.SObjectField f) {
        List<Opcao> out = new List<Opcao>();
        for (Schema.PicklistEntry pe : f.getDescribe().getPicklistValues()) {
            if (pe.isActive()) out.add(new Opcao(pe.getLabel(), pe.getValue()));
        }
        return out;
    }

    private static Boolean valido(Schema.SObjectField f, String v) {
        if (String.isBlank(v)) return false;
        for (Schema.PicklistEntry pe : f.getDescribe().getPicklistValues()) {
            if (pe.isActive() && pe.getValue() == v) return true;
        }
        return false;
    }

    private static String rotuloStatus(String st) {
        return RaizCockpitService.rotulo(Business_Rule__c.Status__c, st);
    }

    private static AuraHandledException aura(String m) {
        AuraHandledException e = new AuraHandledException(m);
        e.setMessage(m);
        return e;
    }

    private static AuraHandledException erroAmigavel(Exception e) {
        if (e instanceof AuraHandledException) return (AuraHandledException) e;
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
                ? 'SEM_PERMISSAO: seu usuário não tem acesso ao cadastro guiado. Peça o permission set EBL_RAIZ_Cockpit.'
                : 'Não foi possível concluir: ' + m
        );
    }
}
