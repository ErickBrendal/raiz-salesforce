import { LightningElement, wire } from 'lwc';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getProfissionais from '@salesforce/apex/RaizSimulationService.getProfissionais';
import simularAusencia from '@salesforce/apex/RaizSimulationService.simularAusencia';

const BRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const NUM = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });

const CLASSE_EFEITO = {
    'Para': 'efeito efeito_para',
    'Fica frágil': 'efeito efeito_fragil',
    'Continua coberto': 'efeito efeito_ok'
};

/**
 * Simulador de ausencia (Metodo RAIZ, Onda 2).
 * Todo numero vem do Apex (RaizSimulationService), calculado sobre
 * habilitacoes reais. O componente so formata e escolhe estados de tela.
 * Nada aqui grava dados: o servico e somente leitura.
 */
export default class RaizSimuladorAusencia extends LightningElement {
    clientes = [];
    profissionais = [];
    contaId = '';
    profissionalId = '';
    resultado;
    erro;
    carregandoLista = true;
    carregandoSim = false;
    listaCarregada = false;

    @wire(getClientes)
    wiredClientes({ data, error }) {
        if (data) {
            this.clientes = data.map((c) => ({ label: c.label, value: c.value }));
        }
        if (error) {
            this.erro = this.mensagem(error);
        }
    }

    @wire(getProfissionais, { contaId: '$contaParam' })
    wiredProfissionais({ data, error }) {
        if (data) {
            this.carregandoLista = false;
            this.listaCarregada = true;
            this.profissionais = data.map((p) => ({ label: p.label, value: p.value }));
            const aindaExiste = this.profissionais.some((p) => p.value === this.profissionalId);
            if (!aindaExiste) {
                this.profissionalId = this.profissionais.length ? this.profissionais[0].value : '';
                this.carregandoSim = !!this.profissionalId;
            }
            this.erro = undefined;
        } else if (error) {
            this.carregandoLista = false;
            this.listaCarregada = true;
            this.profissionais = [];
            this.erro = this.mensagem(error);
        }
    }

    @wire(simularAusencia, { contaId: '$contaParam', profissionalId: '$profissionalParam' })
    wiredSimulacao({ data, error }) {
        if (data) {
            this.carregandoSim = false;
            this.resultado = data;
            this.erro = undefined;
        } else if (error) {
            this.carregandoSim = false;
            this.resultado = undefined;
            this.erro = this.mensagem(error);
        }
    }

    get contaParam() {
        return this.contaId ? this.contaId : null;
    }

    // undefined mantem o wire parado ate existir alguem para simular.
    get profissionalParam() {
        return this.profissionalId ? this.profissionalId : undefined;
    }

    mensagem(e) {
        if (!e) return 'Erro desconhecido.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return 'Erro desconhecido.';
    }

    // ------------------------------------------------------------ eventos
    mudarCliente(evt) {
        this.contaId = evt.detail.value;
        this.carregandoLista = true;
        this.carregandoSim = !!this.profissionalId;
        this.resultado = undefined;
    }

    mudarProfissional(evt) {
        this.profissionalId = evt.detail.value;
        this.carregandoSim = true;
    }

    // ------------------------------------------------------------- estados
    get carregando() {
        return this.carregandoLista || this.carregandoSim;
    }
    get semPermissao() {
        return !!this.erro && this.erro.indexOf('SEM_PERMISSAO') === 0;
    }
    get erroGeral() {
        return !!this.erro && !this.semPermissao;
    }
    get textoPermissao() {
        return this.erro ? this.erro.replace('SEM_PERMISSAO: ', '') : '';
    }
    get vazio() {
        return !this.carregando && !this.erro && this.listaCarregada && this.profissionais.length === 0;
    }
    get temResultado() {
        return !this.carregando && !this.erro && !!this.resultado;
    }
    get temLinhas() {
        return this.temResultado && this.resultado.linhas && this.resultado.linhas.length > 0;
    }
    get temRessalvas() {
        return this.temResultado && this.resultado.ressalvas && this.resultado.ressalvas.length > 0;
    }

    // ------------------------------------------------------- apresentacao
    get exposicaoFmt() {
        return this.resultado ? BRL.format(this.resultado.exposicao || 0) : '';
    }
    get tempoFmt() {
        if (!this.resultado) return '';
        const h = Number(this.resultado.horasParaRestabelecer || 0);
        if (h === 0) return 'sem parada';
        return NUM.format(h) + ' h úteis (~' + NUM.format(Math.ceil(h / 8)) + ' dias)';
    }
    get classeVeredito() {
        if (!this.resultado) return 'veredito';
        if (this.resultado.param > 0) return 'veredito veredito_critico';
        if (this.resultado.ficamFrageis > 0 || this.resultado.processosAvaliados === 0) return 'veredito veredito_atencao';
        return 'veredito veredito_bom';
    }
    get linhas() {
        if (!this.temLinhas) return [];
        return this.resultado.linhas.map((l) => ({
            ...l,
            classeEfeito: CLASSE_EFEITO[l.efeito] || 'efeito',
            exposicaoFmt: l.efeito === 'Para' ? BRL.format(l.exposicao || 0) + (l.exposicaoCompleta ? '' : ' *') : '—',
            transicao: l.aptosAntes + ' → ' + l.aptosDepois
        }));
    }
    get premissas() {
        return (this.resultado && this.resultado.premissas ? this.resultado.premissas : []).map((t, i) => ({ id: 'pm' + i, texto: t }));
    }
    get ressalvas() {
        return (this.resultado && this.resultado.ressalvas ? this.resultado.ressalvas : []).map((t, i) => ({ id: 'rs' + i, texto: t }));
    }
}
