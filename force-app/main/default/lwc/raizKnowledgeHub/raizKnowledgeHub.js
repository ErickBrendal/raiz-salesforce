import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getQuadro from '@salesforce/apex/RaizKnowledgeService.getQuadro';
import criarDocumento from '@salesforce/apex/RaizKnowledgeService.criarDocumento';
import moverDocumento from '@salesforce/apex/RaizKnowledgeService.moverDocumento';

const DATA = new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC' });
const CHIP = {
    'Sem cobertura': 'chip chip_sem',
    'Ponto unico': 'chip chip_ponto',
    'Informacao insuficiente': 'chip',
    'Coberto': 'chip chip_ok'
};
const ROTULO_ESTADO = {
    'Sem cobertura': 'Sem cobertura',
    'Ponto unico': 'Ponto único',
    'Informacao insuficiente': 'Sem informação',
    'Coberto': 'Coberto'
};

/**
 * Knowledge Hub (Metodo RAIZ, Onda 5): ciclo do documento funcional por
 * processo critico. Mover e criar sao cliques explicitos; aprovar e publicar
 * dependem da permissao RAIZ_Aprovar_Documentos (validada no Apex).
 */
export default class RaizKnowledgeHub extends LightningElement {
    clientes = [];
    contaId = '';
    quadro;
    erro;
    erroAcao;
    carregando = true;
    ocupado = false;
    confirmando = null;
    resposta;

    @wire(getClientes)
    wiredClientes({ data, error }) {
        if (data) this.clientes = data.map((c) => ({ label: c.label, value: c.value }));
        if (error) this.erroAcao = 'Lista de clientes indisponível: ' + this.mensagem(error);
    }

    @wire(getQuadro, { contaId: '$contaParam' })
    wiredQuadro(resp) {
        this.resposta = resp;
        if (resp.data) {
            this.quadro = resp.data;
            this.erro = undefined;
            this.carregando = false;
        } else if (resp.error) {
            this.quadro = undefined;
            this.erro = this.mensagem(resp.error);
            this.carregando = false;
        }
    }

    get contaParam() {
        return this.contaId ? this.contaId : null;
    }
    mensagem(e) {
        if (!e) return 'Erro desconhecido.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return 'Erro desconhecido.';
    }

    get semPermissao() {
        return !!this.erro && this.erro.indexOf('SEM_PERMISSAO') === 0;
    }
    get textoPermissao() {
        return this.erro ? this.erro.replace('SEM_PERMISSAO: ', '') : '';
    }
    get erroGeral() {
        return !!this.erro && !this.semPermissao;
    }
    get pronto() {
        return !this.carregando && !this.erro && !!this.quadro;
    }
    get vazio() {
        return this.pronto && this.quadro.documentos === 0 && this.quadro.processosSemDocumento === 0;
    }
    get avisoAprovador() {
        return this.pronto && !this.quadro.podeAprovar;
    }

    get colunas() {
        if (!this.pronto) return [];
        return this.quadro.colunas.map((c) => ({
            ...c,
            backlog: c.chave === 'Backlog',
            cartoes: c.cartoes.map((k) => ({
                ...k,
                chave: k.id || 'p-' + k.processoId,
                chip: CHIP[k.estadoCobertura] || 'chip',
                estadoRotulo: ROTULO_ESTADO[k.estadoCobertura] || '',
                revisaoFmt: k.ultimaRevisao ? 'revisado em ' + DATA.format(new Date(k.ultimaRevisao)) : '',
                temPendencias: k.pendencias && k.pendencias.length > 0 && c.chave !== 'Backlog',
                pendenciasTxt: (k.pendencias || []).join(' · '),
                confirmar: this.confirmando === k.processoId,
                textoAvancar: 'Mover para ' + k.proximaEtapa,
                govClasse: 'gov' + (k.governanca && (k.governanca.indexOf('Bloqueado') === 0 || k.governanca.indexOf('Revisão atrasada') === 0) ? ' gov_alerta' : ''),
                demandasTxt: k.demandasLigadas ? k.demandasLigadas + (k.demandasLigadas === 1 ? ' demanda' : ' demandas') : ''
            }))
        }));
    }
    get premissas() {
        return (this.quadro ? this.quadro.premissas : []).map((t, i) => ({ id: 'pm' + i, texto: t }));
    }

    mudarCliente(evt) {
        this.contaId = evt.detail.value;
        this.carregando = true;
        this.confirmando = null;
    }
    pedirCriacao(evt) {
        this.confirmando = evt.currentTarget.dataset.id;
        this.erroAcao = undefined;
    }
    cancelar() {
        this.confirmando = null;
    }
    async confirmarCriacao(evt) {
        await this.executar(() => criarDocumento({ processoId: evt.currentTarget.dataset.id }));
        this.confirmando = null;
    }
    async avancar(evt) {
        await this.executar(() => moverDocumento({ documentoId: evt.currentTarget.dataset.id, direcao: 1 }));
    }
    async voltar(evt) {
        await this.executar(() => moverDocumento({ documentoId: evt.currentTarget.dataset.id, direcao: -1 }));
    }
    async executar(fn) {
        this.ocupado = true;
        this.erroAcao = undefined;
        try {
            await fn();
            await refreshApex(this.resposta);
        } catch (e) {
            this.erroAcao = this.mensagem(e);
        } finally {
            this.ocupado = false;
        }
    }
}
