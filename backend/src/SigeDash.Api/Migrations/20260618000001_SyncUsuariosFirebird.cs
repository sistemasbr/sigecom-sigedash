using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Api.Migrations
{
    /// <inheritdoc />
    public partial class SyncUsuariosFirebird : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Substitui SenhaHash (BCrypt) por SenhaApp (SHA-1 hex do Sigecom)
            migrationBuilder.RenameColumn(
                name: "SenhaHash",
                table: "UsuariosApp",
                newName: "SenhaApp");

            migrationBuilder.DropColumn(
                name: "Email",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "Departamento",
                table: "UsuariosApp");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "SenhaApp",
                table: "UsuariosApp",
                newName: "SenhaHash");

            migrationBuilder.AddColumn<string>(
                name: "Email",
                table: "UsuariosApp",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Departamento",
                table: "UsuariosApp",
                type: "text",
                nullable: true);
        }
    }
}
