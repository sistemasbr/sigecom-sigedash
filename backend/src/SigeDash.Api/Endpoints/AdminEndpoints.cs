using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;

namespace SigeDash.Api.Endpoints;

public record CriarClienteRequest(string Nome, int CodigoEmpresa, string NomeLoja);
public record CriarUsuarioRequest(string ClienteNome, string Login, string Senha, string Departamento);
public record AlterarSenhaRequest(string ClienteNome, string Login, string NovaSenha);

/// <summary>
/// Endpoints de administração — protegidos por X-Admin-Key (config AdminKey).
/// Usados pela equipe SistemasBr para cadastrar novos clientes e usuários.
/// </summary>
public static class AdminEndpoints
{
    public static void MapAdmin(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        var admin = app.MapGroup("/admin").AddEndpointFilter(AdminKeyFilter(cfg));

        // ── POST /admin/clientes ──────────────────────────────────────────────
        // Cria o cliente e retorna a ChaveApi gerada (necessária para configurar o agente).
        admin.MapPost("/clientes", async (CriarClienteRequest r, AppDbContext db) =>
        {
            if (await db.Clientes.AnyAsync(c => c.Nome == r.Nome))
                return Results.Conflict(new { erro = $"Cliente '{r.Nome}' já existe." });

            var chave = GerarChave(r.Nome);
            var cliente = new Cliente { Nome = r.Nome, ChaveApi = chave, Ativo = true };
            db.Clientes.Add(cliente);
            await db.SaveChangesAsync();

            db.Lojas.Add(new Loja
            {
                ClienteId = cliente.Id,
                CodigoEmpresa = r.CodigoEmpresa,
                Nome = r.NomeLoja
            });
            await db.SaveChangesAsync();

            return Results.Ok(new
            {
                clienteId  = cliente.Id,
                nome       = cliente.Nome,
                chaveApi   = cliente.ChaveApi,
                mensagem   = "Configure o agente com a ChaveApi acima."
            });
        });

        // ── POST /admin/usuarios ──────────────────────────────────────────────
        // Cria um usuário do app para um cliente existente.
        admin.MapPost("/usuarios", async (CriarUsuarioRequest r, AppDbContext db) =>
        {
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.ClienteNome && c.Ativo);
            if (cliente is null)
                return Results.NotFound(new { erro = $"Cliente '{r.ClienteNome}' não encontrado." });

            if (await db.UsuariosApp.AnyAsync(u => u.ClienteId == cliente.Id && u.Login == r.Login))
                return Results.Conflict(new { erro = $"Login '{r.Login}' já existe para este cliente." });

            db.UsuariosApp.Add(new UsuarioApp
            {
                ClienteId    = cliente.Id,
                Login        = r.Login.ToUpper(),
                Departamento = r.Departamento,
                SenhaHash    = BCrypt.Net.BCrypt.HashPassword(r.Senha)
            });
            await db.SaveChangesAsync();

            return Results.Ok(new { ok = true, login = r.Login.ToUpper(), cliente = cliente.Nome });
        });

        // ── PUT /admin/usuarios/senha ─────────────────────────────────────────
        // Redefine a senha de um usuário (suporte).
        admin.MapPut("/usuarios/senha", async (AlterarSenhaRequest r, AppDbContext db) =>
        {
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.ClienteNome && c.Ativo);
            if (cliente is null)
                return Results.NotFound(new { erro = "Cliente não encontrado." });

            var user = await db.UsuariosApp
                .FirstOrDefaultAsync(u => u.ClienteId == cliente.Id && u.Login == r.Login.ToUpper());
            if (user is null)
                return Results.NotFound(new { erro = "Usuário não encontrado." });

            user.SenhaHash = BCrypt.Net.BCrypt.HashPassword(r.NovaSenha);
            await db.SaveChangesAsync();
            return Results.Ok(new { ok = true });
        });

        // ── GET /admin/clientes ───────────────────────────────────────────────
        // Lista todos os clientes (para o suporte visualizar).
        admin.MapGet("/clientes", async (AppDbContext db) =>
            await db.Clientes
                .Select(c => new { c.Id, c.Nome, c.ChaveApi, c.Ativo })
                .ToListAsync());
    }

    // Gera chave no formato NOMEDOCLIENTE-ANO-XXXXXXXX (8 chars hex)
    private static string GerarChave(string nomeCliente)
    {
        var prefixo = new string(nomeCliente.ToUpper()
            .Where(char.IsLetterOrDigit).Take(12).ToArray());
        var sufixo = Guid.NewGuid().ToString("N")[..8].ToUpper();
        return $"{prefixo}-{DateTime.UtcNow.Year}-{sufixo}";
    }

    // Middleware inline: valida X-Admin-Key
    private static Func<EndpointFilterInvocationContext, EndpointFilterDelegate, ValueTask<object?>> AdminKeyFilter(IConfiguration cfg)
        => async (ctx, next) =>
        {
            var adminKey = cfg["AdminKey"];
            if (string.IsNullOrEmpty(adminKey))
                return Results.Problem("AdminKey não configurada no servidor.", statusCode: 500);

            var headerKey = ctx.HttpContext.Request.Headers["X-Admin-Key"].ToString();
            if (headerKey != adminKey)
                return Results.Unauthorized();

            return await next(ctx);
        };
}
