using SigeDash.Api.Modelos;

namespace SigeDash.Api.Data;

/// <summary>
/// Seed de DESENVOLVIMENTO. Cria o cliente "5 Estrelas", a loja (empresa 1) e os
/// usuarios do app com senha em BCrypt — convertidos das senhas reais do SIGECOM
/// (que eram SHA-1 fraco). Roda so quando o banco esta vazio.
/// NAO usar em producao: a migracao real dos usuarios vem do agente/painel admin.
/// </summary>
public static class SeedData
{
    // chave_api de teste usada pelo agente (header X-SigeDash-Key)
    public const string ChaveApiTeste = "TESTE-5ESTRELAS-0001";

    public static void Seed(AppDbContext db)
    {
        if (db.Clientes.Any()) return; // ja semeado

        var cliente = new Cliente
        {
            Nome = "5 Estrelas",
            ChaveApi = ChaveApiTeste,
            Ativo = true,
            Lojas = new List<Loja>
            {
                new Loja { CodigoEmpresa = 1, Nome = "Matriz" }
            }
        };
        db.Clientes.Add(cliente);
        db.SaveChanges();
        // Usuários são sincronizados automaticamente pelo agente via POST /ingest/usuarios
    }
}
