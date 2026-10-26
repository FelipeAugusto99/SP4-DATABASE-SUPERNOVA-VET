package br.com.supernovavet.repository;

import java.sql.Date;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.ColumnMapRowMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

/**
 * Chama as procedures do package PKG_PET_APP (Oracle).
 * Os nomes dos parametros (P_NM_TUTOR etc.) sao os mesmos do package.
 */
@Repository
public class PetProcedureRepository {

    private final JdbcTemplate jdbc;

    public PetProcedureRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private SimpleJdbcCall chamada(String procedure) {
        return new SimpleJdbcCall(jdbc)
                .withCatalogName("PKG_PET_APP")   // catalogo = nome do package
                .withProcedureName(procedure);
    }

    public Long inserirTutor(String nome, String email, String telefone) {
        Map<String, Object> out = chamada("PR_INSERIR_TUTOR").execute(
                new MapSqlParameterSource()
                        .addValue("P_NM_TUTOR", nome)
                        .addValue("P_DS_EMAIL", email)
                        .addValue("P_NR_TELEFONE", telefone));
        return ((Number) out.get("P_ID_TUTOR")).longValue();
    }

    public Long inserirPet(String nome, String especie, String raca, Integer idade,
                           Double peso, String sexo, Long idTutor) {
        Map<String, Object> out = chamada("PR_INSERIR_PET").execute(
                new MapSqlParameterSource()
                        .addValue("P_NM_PET", nome)
                        .addValue("P_DS_ESPECIE", especie)
                        .addValue("P_DS_RACA", raca)
                        .addValue("P_NR_IDADE", idade)
                        .addValue("P_NR_PESO", peso)
                        .addValue("P_DS_SEXO", sexo)
                        .addValue("P_ID_TUTOR", idTutor));
        return ((Number) out.get("P_ID_PET")).longValue();
    }

    public Long registrarVacina(String vacina, LocalDate aplicacao, LocalDate proximaDose, Long idPet) {
        Map<String, Object> out = chamada("PR_REGISTRAR_VACINA").execute(
                new MapSqlParameterSource()
                        .addValue("P_NM_VACINA", vacina)
                        .addValue("P_DT_APLICACAO", Date.valueOf(aplicacao))
                        .addValue("P_DT_PROXIMA_DOSE", proximaDose == null ? null : Date.valueOf(proximaDose))
                        .addValue("P_ID_PET", idPet));
        return ((Number) out.get("P_ID_VACINA")).longValue();
    }

    public void atualizarPeso(Long idPet, Double peso) {
        chamada("PR_ATUALIZAR_PESO_PET").execute(
                new MapSqlParameterSource()
                        .addValue("P_ID_PET", idPet)
                        .addValue("P_NR_PESO", peso));
    }

    public void excluirPet(Long idPet) {
        chamada("PR_EXCLUIR_PET").execute(
                new MapSqlParameterSource().addValue("P_ID_PET", idPet));
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> listarPets() {
        // procedure com SYS_REFCURSOR de saida: o Spring le o cursor como lista
        SimpleJdbcCall call = chamada("PR_LISTAR_PETS")
                .returningResultSet("P_CURSOR", new ColumnMapRowMapper());
        return (List<Map<String, Object>>) call.execute().get("P_CURSOR");
    }
}
