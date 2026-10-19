import { createElement } from 'lwc';
import RaizKnowledgeHub from 'c/raizKnowledgeHub';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getQuadro from '@salesforce/apex/RaizKnowledgeService.getQuadro';
import criarDocumento from '@salesforce/apex/RaizKnowledgeService.criarDocumento';
import moverDocumento from '@salesforce/apex/RaizKnowledgeService.moverDocumento';

jest.mock('@salesforce/apex/RaizCockpitService.getClientes', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizKnowledgeService.getQuadro', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizKnowledgeService.criarDocumento', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizKnowledgeService.moverDocumento', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), { virtual: true });

const col = (chave, rotulo, cartoes) => ({ chave, rotulo, total: cartoes.length, cartoes });
const QUADRO = {
    podeAprovar: false, documentos: 2, publicados: 1, processosSemDocumento: 1, premissas: ['Quem escreve não aprova.'],
    colunas: [
        col('Backlog', 'Backlog', [{ processoId: 'p1', titulo: 'Roteiro de produção', estadoCobertura: 'Ponto unico', criticidade: 'Crítico', pendencias: [], podeAvancar: true, proximaEtapa: 'Em elaboração' }]),
        col('Draft', 'Em elaboração', [{ id: 'd1', processoId: 'p2', titulo: 'Registro — Fechamento', estadoCobertura: 'Coberto', criticidade: 'Alto', pendencias: ['Propósito', 'Descrição'], podeAvancar: true, podeVoltar: false, proximaEtapa: 'Em revisão', demandasLigadas: 2 }]),
        col('Em Analise', 'Em revisão', [{ id: 'd2', processoId: 'p3', titulo: 'Registro — Apuração', estadoCobertura: 'Ponto unico', pendencias: [], podeAvancar: false, podeVoltar: true, proximaEtapa: 'Aprovado', motivoBloqueio: 'Exige permissão de aprovação.' }]),
        col('Aprovada', 'Aprovado', []),
        col('Publicada', 'Publicado', [{ id: 'd3', processoId: 'p4', titulo: 'Registro — Comissão', estadoCobertura: 'Coberto', pendencias: [], podeAvancar: false, podeVoltar: false, ultimaRevisao: '2026-10-17' }])
    ]
};
const flush = () => new Promise((r) => setTimeout(r, 0));
const montar = () => { const el = createElement('c-raiz-knowledge-hub', { is: RaizKnowledgeHub }); document.body.appendChild(el); return el; };
const q = (el, s) => el.shadowRoot.querySelector(s);

describe('c-raiz-knowledge-hub', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); jest.clearAllMocks(); });

    it('mostra as cinco colunas, pendencias e bloqueio do aprovador', async () => {
        const el = montar();
        expect(q(el, '[data-id="carregando"]')).not.toBeNull();
        getClientes.emit([{ label: 'Todos', value: '' }]);
        getQuadro.emit(QUADRO);
        await flush();
        expect(el.shadowRoot.querySelectorAll('.coluna').length).toBe(5);
        expect(q(el, '[data-id="resumo"]').textContent).toContain('2 documentos');
        expect(q(el, '[data-coluna="Draft"]').textContent).toContain('Falta: Propósito · Descrição');
        expect(q(el, '[data-coluna="Draft"]').textContent).toContain('2 demandas');
        expect(q(el, '[data-coluna="Em Analise"]').textContent).toContain('Exige permissão');
        expect(q(el, '[data-coluna="Publicada"]').textContent).toContain('revisado em 17/10/2026');
        expect(q(el, '[data-id="aviso-aprovador"]')).not.toBeNull();
        expect(q(el, '.chip_ponto').textContent).toBe('Ponto único');
    });

    it('criar exige confirmacao; avancar e voltar chamam o Apex; erro aparece', async () => {
        criarDocumento.mockResolvedValue('d9');
        moverDocumento.mockResolvedValue();
        const el = montar();
        getQuadro.emit(QUADRO);
        await flush();
        q(el, 'button[data-acao="criar"]').click();
        await flush();
        expect(criarDocumento).not.toHaveBeenCalled();
        q(el, 'button[data-acao="cancelar"]').click();
        await flush();
        q(el, 'button[data-acao="criar"]').click();
        await flush();
        q(el, 'button[data-acao="confirmar"]').click();
        await flush();
        expect(criarDocumento).toHaveBeenCalledWith({ processoId: 'p1' });
        q(el, 'button[data-acao="avancar"]').click();
        await flush();
        expect(moverDocumento).toHaveBeenCalledWith({ documentoId: 'd1', direcao: 1 });
        moverDocumento.mockRejectedValue({ body: { message: 'Para mover o documento para Aprovada/Publicada, preencha: Propósito' } });
        q(el, 'button[data-acao="voltar"]').click();
        await flush();
        expect(moverDocumento).toHaveBeenCalledWith({ documentoId: 'd2', direcao: -1 });
        expect(q(el, '[data-id="erro-acao"]').textContent).toContain('preencha');
    });

    it('estados de permissao, erro e vazio', async () => {
        let el = montar();
        getQuadro.error({ message: 'SEM_PERMISSAO: peça o permission set EBL_RAIZ_Cockpit.' });
        await flush();
        expect(q(el, '[data-id="sem-permissao"]').textContent).toContain('EBL_RAIZ_Cockpit');
        document.body.removeChild(el);
        el = montar();
        getQuadro.error({ message: 'falhou' });
        await flush();
        expect(q(el, '[data-id="erro"]').textContent).toContain('falhou');
        document.body.removeChild(el);
        el = montar();
        getQuadro.emit({ ...QUADRO, podeAprovar: true, documentos: 0, processosSemDocumento: 0, colunas: QUADRO.colunas.map((c) => ({ ...c, cartoes: [], total: 0 })) });
        await flush();
        expect(q(el, '[data-id="vazio"]')).not.toBeNull();
        expect(q(el, '[data-id="aviso-aprovador"]')).toBeNull();
        q(el, '[data-id="cliente"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'c1' } }));
        await flush();
        expect(getQuadro.getLastConfig()).toEqual({ contaId: 'c1' });
    });
    it('mostra a situacao da governanca no cartao e destaca bloqueio (Onda 7)', async () => {
        const el = montar();
        const q2 = JSON.parse(JSON.stringify(QUADRO));
        q2.colunas[2].cartoes[0].governanca = 'Bloqueado: falta Revisor';
        q2.colunas[1].cartoes[0].governanca = 'Devolvido para elaboração em 18/10/2026';
        getQuadro.emit(q2);
        await flush();
        const rev = q(el, '[data-coluna="Em Analise"] [data-id="governanca"]');
        expect(rev.textContent).toBe('Bloqueado: falta Revisor');
        expect(rev.className).toContain('gov_alerta');
        expect(q(el, '[data-coluna="Draft"] [data-id="governanca"]').className).not.toContain('gov_alerta');
    });
});
