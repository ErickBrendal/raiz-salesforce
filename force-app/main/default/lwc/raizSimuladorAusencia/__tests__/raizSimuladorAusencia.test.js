import { createElement } from 'lwc';
import RaizSimuladorAusencia from 'c/raizSimuladorAusencia';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getProfissionais from '@salesforce/apex/RaizSimulationService.getProfissionais';
import simularAusencia from '@salesforce/apex/RaizSimulationService.simularAusencia';

jest.mock('@salesforce/apex/RaizCockpitService.getClientes', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizSimulationService.getProfissionais', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizSimulationService.simularAusencia', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });

const RESULTADO = {
    pessoa: 'Ana Teste',
    processosAvaliados: 3,
    param: 1,
    ficamFrageis: 1,
    continuam: 1,
    exposicao: 16000,
    exposicaoIncompleta: 0,
    horasParaRestabelecer: 16,
    veredito: 'Exposicao contida, mas existente. 1 processo(s) param e 1 ficam frageis.',
    premissas: ['Nada e gravado: a simulacao e somente leitura.'],
    ressalvas: [],
    linhas: [
        { processoId: 'a01', processo: 'Fechamento', area: 'Fiscal', criticidade: 'Critico', aptosAntes: 1, aptosDepois: 0,
          efeito: 'Para', substitutos: 'Ninguem', exposicao: 16000, exposicaoCompleta: true },
        { processoId: 'a02', processo: 'Apuracao', area: 'Fiscal', criticidade: 'Alto', aptosAntes: 2, aptosDepois: 1,
          efeito: 'Fica frágil', substitutos: 'Bruno Teste', exposicao: 0, exposicaoCompleta: true }
    ]
};

const flush = () => Promise.resolve().then(() => Promise.resolve());

function montar() {
    const el = createElement('c-raiz-simulador-ausencia', { is: RaizSimuladorAusencia });
    document.body.appendChild(el);
    return el;
}
const q = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-raiz-simulador-ausencia', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('comeca em carregamento, sem inventar numero', () => {
        const el = montar();
        expect(q(el, 'carregando')).not.toBeNull();
        expect(q(el, 'resultado')).toBeNull();
    });

    it('mostra o resultado formatado em pt-BR', async () => {
        const el = montar();
        getClientes.emit([{ label: 'Todos os clientes', value: '' }]);
        getProfissionais.emit([{ label: 'Ana Teste (3 habilitacoes)', value: 'p1', habilitacoes: 3 }]);
        await flush();
        simularAusencia.emit(RESULTADO);
        await flush();
        expect(q(el, 'carregando')).toBeNull();
        expect(q(el, 'param').textContent).toBe('1');
        expect(q(el, 'frageis').textContent).toBe('1');
        expect(q(el, 'exposicao').textContent.replace(/\s/g, ' ')).toBe('R$ 16.000');
        expect(q(el, 'tempo').textContent).toBe('16 h úteis (~2 dias)');
        expect(q(el, 'veredito').className).toContain('veredito_critico');
        const linhas = q(el, 'linhas').querySelectorAll('tbody tr');
        expect(linhas.length).toBe(2);
        expect(linhas[0].textContent).toContain('1 → 0');
        expect(linhas[1].textContent).toContain('—');
    });

    it('sem habilitacao mostra estado vazio, nao verde', async () => {
        const el = montar();
        getProfissionais.emit([]);
        await flush();
        expect(q(el, 'vazio')).not.toBeNull();
        expect(q(el, 'resultado')).toBeNull();
    });

    it('falta de permissao tem mensagem propria', async () => {
        const el = montar();
        getProfissionais.error({ message: 'SEM_PERMISSAO: peca o permission set EBL_RAIZ_Cockpit.' });
        await flush();
        expect(q(el, 'sem-permissao')).not.toBeNull();
        expect(q(el, 'sem-permissao').textContent).toContain('EBL_RAIZ_Cockpit');
        expect(q(el, 'erro')).toBeNull();
    });

    it('erro generico aparece como erro', async () => {
        const el = montar();
        getProfissionais.emit([{ label: 'Ana', value: 'p1', habilitacoes: 1 }]);
        await flush();
        simularAusencia.error({ message: 'Nao foi possivel simular: timeout' });
        await flush();
        expect(q(el, 'erro')).not.toBeNull();
        expect(q(el, 'resultado')).toBeNull();
    });

    it('troca de cliente e de pessoa recalcula e nada parado fica verde', async () => {
        const el = montar();
        getClientes.emit([{ label: 'Todos', value: '' }, { label: 'Aurora', value: 'c1' }]);
        getProfissionais.emit([{ label: 'Ana', value: 'p1', habilitacoes: 1 }, { label: 'Bruno', value: 'p2', habilitacoes: 1 }]);
        await flush();
        q(el, 'profissional').dispatchEvent(new CustomEvent('change', { detail: { value: 'p2' } }));
        await flush();
        expect(q(el, 'carregando')).not.toBeNull();
        expect(simularAusencia.getLastConfig()).toEqual({ contaId: null, profissionalId: 'p2' });
        simularAusencia.emit({ ...RESULTADO, param: 0, ficamFrageis: 0, continuam: 2, exposicao: 0,
            horasParaRestabelecer: 0, linhas: [], ressalvas: ['Teste de ressalva'] });
        await flush();
        expect(q(el, 'veredito').className).toContain('veredito_bom');
        expect(q(el, 'tempo').textContent).toBe('sem parada');
        expect(el.shadowRoot.querySelector('.ressalvas').textContent).toContain('Teste de ressalva');
        q(el, 'cliente').dispatchEvent(new CustomEvent('change', { detail: { value: 'c1' } }));
        await flush();
        expect(getProfissionais.getLastConfig()).toEqual({ contaId: 'c1' });
        getClientes.error({ message: 'falha clientes' });
        await flush();
        expect(q(el, 'erro').textContent).toContain('falha clientes');
    });
});
