import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContexto from '@salesforce/apex/RaizJourneyService.getContexto';
import getSituacao from '@salesforce/apex/RaizJourneyService.getSituacao';
import validar from '@salesforce/apex/RaizJourneyService.validar';
import salvar from '@salesforce/apex/RaizJourneyService.salvar';

/**
 * RAIZ Guided Journey — cadastro assistido de conhecimento (Onda 6).
 *
 * Sete telas; NADA e gravado antes da tela 7. As regras ficam no Apex
 * (RaizJourneyService): ao avancar, a tela pede validar() e mostra so os
 * bloqueios daquela etapa. Os campos de texto formatado usam um buffer para
 * nao re-renderizar o editor a cada tecla (o cursor pularia).
 */
export const ETAPAS = [
    { n: 1, rotulo: 'Início' },
    { n: 2, rotulo: 'Processo' },
    { n: 3, rotulo: 'Classificação' },
    { n: 4, rotulo: 'Responsabilidade' },
    { n: 5, rotulo: 'Conteúdo' },
    { n: 6, rotulo: 'Revisão' },
    { n: 7, rotulo: 'Confirmação' }
];

const RICOS = ['resumo', 'preRequisitos', 'etapas', 'resultadoEsperado', 'excecoes', 'contingencia', 'referencias'];

const CONTEUDO = [
    {
        campo: 'preRequisitos',
        rotulo: 'Pré-requisitos',
        ajuda: 'Acessos, sistemas e informações que a pessoa precisa ter antes de começar.'
    },
    {
        campo: 'etapas',
        rotulo: 'Etapas operacionais',
        ajuda: 'O passo a passo, na ordem em que é feito. Escreva para alguém que nunca executou o processo.'
    },
    {
        campo: 'resultadoEsperado',
        rotulo: 'Resultado esperado',
        ajuda: 'Como saber que deu certo. Necessário para aprovar.'
    },
    {
        campo: 'excecoes',
        rotulo: 'Exceções',
        ajuda: 'Situações fora do padrão e como tratá-las. Necessário para aprovar.'
    },
    {
        campo: 'contingencia',
        rotulo: 'Plano de contingência',
        ajuda: 'O que fazer se o procedimento não puder ser executado como descrito.'
    },
    { campo: 'referencias', rotulo: 'Referências', ajuda: 'Links, normas e documentos relacionados.' }
];

const ESTADO_COBERTURA = {
    'Sem cobertura': 'Sem cobertura',
    'Ponto unico': 'Ponto único de falha',
    'Informacao insuficiente': 'Informação insuficiente',
    Coberto: 'Coberto'
};

function vazio() {
    return {
        documentoId: null,
        processoId: null,
        titulo: '',
        tipo: '',
        categoria: '',
        resumo: '',
        palavrasChave: '',
        revisorId: '',
        dataReferencia: null,
        proximaRevisao: null,
        prazoRevisao: null,
        criticidade: '',
        preRequisitos: '',
        etapas: '',
        resultadoEsperado: '',
        excecoes: '',
        contingencia: '',
        referencias: ''
    };
}

function semHtml(v) {
    return (v || '')
        .replace(/<[^>]*>/g, ' ')
        .replace(/&nbsp;/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

export default class RaizGuidedJourney extends NavigationMixin(LightningElement) {
    etapa = 1;
    visitada = 1;
    contexto;
    carregando = true;
    erroCarga;
    erroEtapa = [];
    situacao;
    dados = vazio();
    _buf = {};
    revisao;
    ocupado = false;
    erroSalvar;
    resultado;

    connectedCallback() {
        this.carregar();
    }

    carregar() {
        this.carregando = true;
        getContexto()
            .then((c) => {
                this.contexto = c;
                this.erroCarga = undefined;
            })
            .catch((e) => {
                this.erroCarga = this.msg(e);
            })
            .finally(() => {
                this.carregando = false;
            });
    }

    msg(e) {
        if (!e) return 'Erro desconhecido.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return 'Erro desconhecido.';
    }

    // ------------------------------------------------------------ estado
    get semPermissao() {
        return !!this.erroCarga && this.erroCarga.indexOf('SEM_PERMISSAO') === 0;
    }
    get textoErroCarga() {
        return this.erroCarga ? this.erroCarga.replace('SEM_PERMISSAO: ', '') : '';
    }
    get pronto() {
        return !this.carregando && !this.erroCarga && !!this.contexto;
    }
    get e1() {
        return this.etapa === 1;
    }
    get e2() {
        return this.etapa === 2;
    }
    get e3() {
        return this.etapa === 3;
    }
    get e4() {
        return this.etapa === 4;
    }
    get e5() {
        return this.etapa === 5;
    }
    get e6() {
        return this.etapa === 6;
    }
    get e7() {
        return this.etapa === 7;
    }
    get passos() {
        return ETAPAS.map((p) => {
            let cls = 'passo';
            if (p.n === this.etapa) cls += ' passo_atual';
            else if (p.n <= this.visitada) cls += ' passo_feito';
            return {
                ...p,
                cls,
                bloqueado: p.n > this.visitada || !!this.resultado,
                aria: p.n === this.etapa ? 'step' : null
            };
        });
    }
    get mostraVoltar() {
        return this.etapa > 1 && !this.resultado;
    }
    get mostraProximo() {
        return this.etapa < 7 && this.etapa > 1;
    }
    get proximoDesabilitado() {
        return this.ocupado || (this.etapa === 2 && !this.podeSeguirProcesso);
    }
    get rotuloProximo() {
        return this.etapa === 6 ? 'Ir para a confirmação' : 'Próximo';
    }

    // ----------------------------------------------------------- opcoes
    get opcoesProcesso() {
        return (this.contexto ? this.contexto.processos : []).map((p) => ({
            label: p.nome + ' · ' + p.situacaoDocumento,
            value: p.id
        }));
    }
    get opcoesTipo() {
        return this.contexto ? this.contexto.tipos : [];
    }
    get opcoesCategoria() {
        return this.contexto ? this.contexto.categorias : [];
    }
    get opcoesCriticidade() {
        return this.contexto ? this.contexto.criticidades : [];
    }
    get opcoesRevisor() {
        const lista = (this.contexto ? this.contexto.revisores : []).map((r) => ({ label: r.nome, value: r.id }));
        return [{ label: 'Definir depois', value: '' }, ...lista];
    }
    get semRevisores() {
        return !!this.contexto && this.contexto.revisores.length === 0;
    }
    get processo() {
        if (!this.contexto || !this.dados.processoId) return null;
        return this.contexto.processos.find((p) => p.id === this.dados.processoId) || null;
    }
    get coberturaProcesso() {
        const p = this.processo;
        return p ? ESTADO_COBERTURA[p.estadoCobertura] || 'Não calculada' : '';
    }
    get podeSeguirProcesso() {
        return !!this.situacao && this.situacao.podeContinuar;
    }
    get situacaoBloqueada() {
        return !!this.situacao && !this.situacao.podeContinuar;
    }
    get situacaoRascunho() {
        return !!this.situacao && this.situacao.estado === 'RASCUNHO';
    }
    get conteudo() {
        return CONTEUDO.map((c) => ({ ...c, valor: this.valor(c.campo) }));
    }
    get usuarioNome() {
        return this.contexto ? this.contexto.usuarioNome : '';
    }

    valor(campo) {
        return Object.prototype.hasOwnProperty.call(this._buf, campo) ? this._buf[campo] : this.dados[campo];
    }

    // ---------------------------------------------------------- eventos
    comecar() {
        this.irPara(2);
    }

    escolherProcesso(event) {
        const id = event.detail.value;
        this.situacao = undefined;
        this.erroEtapa = [];
        this.ocupado = true;
        getSituacao({ processoId: id })
            .then((s) => {
                this.situacao = s;
                const base = vazio();
                if (s.estado === 'RASCUNHO' && s.dados) {
                    Object.keys(base).forEach((k) => {
                        if (s.dados[k] !== undefined && s.dados[k] !== null) base[k] = s.dados[k];
                    });
                }
                base.processoId = id;
                base.documentoId = s.dados ? s.dados.documentoId || null : null;
                const p = this.contexto.processos.find((x) => x.id === id);
                if (p && !base.titulo) base.titulo = 'Registro — ' + p.nome;
                if (p && !base.criticidade && p.criticidadeDocumento) base.criticidade = p.criticidadeDocumento;
                this._buf = {};
                this.dados = base;
            })
            .catch((e) => {
                this.erroEtapa = [this.msg(e)];
            })
            .finally(() => {
                this.ocupado = false;
            });
    }

    mudarCampo(event) {
        const campo = event.target.dataset.campo;
        const v = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.dados = { ...this.dados, [campo]: v === '' && campo.endsWith('Id') ? null : v };
    }

    mudarRico(event) {
        // Buffer: nao reatribui this.dados (evita re-render do editor).
        this._buf[event.target.dataset.campo] = event.target.value;
    }

    sincronizarBuffer() {
        if (Object.keys(this._buf).length) {
            this.dados = { ...this.dados, ...this._buf };
            this._buf = {};
        }
    }

    payload() {
        this.sincronizarBuffer();
        const d = { ...this.dados };
        ['revisorId', 'documentoId'].forEach((k) => {
            if (!d[k]) d[k] = null;
        });
        ['dataReferencia', 'proximaRevisao', 'prazoRevisao'].forEach((k) => {
            if (!d[k]) d[k] = null;
        });
        return JSON.stringify(d);
    }

    voltar() {
        this.sincronizarBuffer();
        this.erroEtapa = [];
        if (this.etapa > 1) this.irPara(this.etapa - 1);
    }

    clicarPasso(event) {
        const n = Number(event.currentTarget.dataset.n);
        if (n <= this.visitada && !this.resultado) {
            this.sincronizarBuffer();
            this.erroEtapa = [];
            this.irPara(n);
        }
    }

    corrigir(event) {
        this.irPara(Number(event.currentTarget.dataset.n));
    }

    proximo() {
        const atual = this.etapa;
        this.ocupado = true;
        this.erroEtapa = [];
        validar({ dadosJson: this.payload(), encaminhar: true })
            .then((rv) => {
                if (atual === 6) {
                    this.revisao = rv;
                    this.irPara(7);
                    return;
                }
                const daqui = rv.bloqueios.filter((b) => b.etapa <= atual).map((b) => b.mensagem);
                if (daqui.length) {
                    this.erroEtapa = daqui;
                    return;
                }
                if (atual + 1 === 6) this.revisao = rv;
                this.irPara(atual + 1);
            })
            .catch((e) => {
                this.erroEtapa = [this.msg(e)];
            })
            .finally(() => {
                this.ocupado = false;
            });
    }

    irPara(n) {
        this.etapa = n;
        if (n > this.visitada) this.visitada = n;
        if (n === 6) this.atualizarRevisao();
    }

    atualizarRevisao() {
        validar({ dadosJson: this.payload(), encaminhar: true })
            .then((rv) => {
                this.revisao = rv;
            })
            .catch((e) => {
                this.erroEtapa = [this.msg(e)];
            });
    }

    // ---------------------------------------------------------- revisao
    get bloqueios() {
        return this.revisao
            ? this.revisao.bloqueios.map((b, i) => ({ key: 'b' + i, etapa: b.etapa, mensagem: b.mensagem, rotulo: 'Corrigir na tela ' + b.etapa }))
            : [];
    }
    get temBloqueios() {
        return this.bloqueios.length > 0;
    }
    get avisos() {
        return this.revisao ? this.revisao.avisos.map((a, i) => ({ key: 'a' + i, texto: a })) : [];
    }
    get temAvisos() {
        return this.avisos.length > 0;
    }
    get resumoLinhas() {
        const d = this.dados;
        const p = this.processo;
        const rot = (lista, v) => {
            const o = (lista || []).find((x) => x.value === v);
            return o ? o.label : '';
        };
        const rev = (this.contexto ? this.contexto.revisores : []).find((r) => r.id === d.revisorId);
        const linhas = [
            { k: 'Processo', v: p ? p.nome : '', n: 2 },
            { k: 'Título', v: d.titulo, n: 3 },
            { k: 'Tipo', v: rot(this.opcoesTipo, d.tipo), n: 3 },
            { k: 'Categoria', v: rot(this.opcoesCategoria, d.categoria), n: 3 },
            { k: 'Resumo e finalidade', v: semHtml(d.resumo), n: 3 },
            { k: 'Palavras-chave', v: d.palavrasChave, n: 3 },
            { k: 'Autor', v: this.usuarioNome, n: 4 },
            { k: 'Revisor', v: rev ? rev.nome : '', n: 4 },
            { k: 'Criticidade', v: rot(this.opcoesCriticidade, d.criticidade), n: 4 },
            { k: 'Data de referência', v: d.dataReferencia, n: 4 },
            { k: 'Próxima revisão', v: d.proximaRevisao, n: 4 },
            { k: 'Prazo da revisão', v: d.prazoRevisao, n: 4 }
        ];
        CONTEUDO.forEach((c) => linhas.push({ k: c.rotulo, v: semHtml(d[c.campo]), n: 5 }));
        return linhas.map((l, i) => {
            const texto = l.v ? String(l.v) : '';
            return {
                key: 'r' + i,
                k: l.k,
                n: l.n,
                v: texto.length > 160 ? texto.slice(0, 157) + '…' : texto || 'Não preenchido',
                cls: texto ? 'res-v' : 'res-v res-v_vazio'
            };
        });
    }

    // ------------------------------------------------------------ salvar
    get naoPodeSalvar() {
        return this.ocupado || this.temBloqueios;
    }
    salvarRascunho() {
        this.gravar(false);
    }
    salvarEncaminhar() {
        this.gravar(true);
    }
    gravar(encaminhar) {
        if (this.ocupado) return;
        this.ocupado = true;
        this.erroSalvar = undefined;
        salvar({ dadosJson: this.payload(), encaminhar })
            .then((r) => {
                this.resultado = r;
            })
            .catch((e) => {
                this.erroSalvar = this.msg(e);
            })
            .finally(() => {
                this.ocupado = false;
            });
    }
    get statusResultado() {
        if (!this.resultado) return '';
        return this.resultado.encaminhado ? 'Encaminhado para revisão' : 'Salvo como rascunho';
    }
    get tituloResultado() {
        if (!this.resultado) return '';
        return this.resultado.criado ? 'Documento criado' : 'Documento atualizado';
    }
    get textoCartao() {
        const c = this.resultado && this.resultado.cartao;
        if (!c || !c.id) return 'Kanban não atualizado.';
        return 'Cartão do Kanban ' + c.acao + ' na coluna "' + c.etapa + '".';
    }
    get avisosResultado() {
        return this.resultado ? this.resultado.avisos.map((a, i) => ({ key: 'ar' + i, texto: a })) : [];
    }
    get temAvisosResultado() {
        return this.avisosResultado.length > 0;
    }
    get passosResultado() {
        return this.resultado ? this.resultado.proximosPassos.map((a, i) => ({ key: 'p' + i, texto: a })) : [];
    }

    abrirDocumento() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.resultado.documentoId, objectApiName: 'Business_Rule__c', actionName: 'view' }
        });
    }
    abrirHub() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'RAIZ_Knowledge_Hub' } });
    }
    recomecar() {
        this.resultado = undefined;
        this.revisao = undefined;
        this.situacao = undefined;
        this.erroSalvar = undefined;
        this.erroEtapa = [];
        this.dados = vazio();
        this._buf = {};
        this.etapa = 1;
        this.visitada = 1;
        this.carregar();
    }

    get erroEtapaLista() {
        return this.erroEtapa.map((m, i) => ({ key: 'e' + i, texto: m }));
    }
    get temErroEtapa() {
        return this.erroEtapa.length > 0;
    }
    get ricos() {
        return RICOS;
    }
}
