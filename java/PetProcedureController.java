package br.com.supernovavet.controller;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import br.com.supernovavet.repository.PetProcedureRepository;

/** Endpoints que executam as procedures do Oracle (para demonstrar no video). */
@RestController
@RequestMapping("/api/procedures")
public class PetProcedureController {

    private final PetProcedureRepository repo;

    public PetProcedureController(PetProcedureRepository repo) {
        this.repo = repo;
    }

    // POST /api/procedures/tutores?nome=Joao&email=joao@x.com&telefone=11900000000
    @PostMapping("/tutores")
    public Map<String, Object> inserirTutor(@RequestParam String nome, @RequestParam String email,
                                            @RequestParam(required = false) String telefone) {
        return Map.of("id_tutor", repo.inserirTutor(nome, email, telefone));
    }

    // POST /api/procedures/pets?nome=Bolt&especie=Cachorro&raca=Beagle&idade=9&peso=12.3&sexo=M&idTutor=1
    @PostMapping("/pets")
    public Map<String, Object> inserirPet(@RequestParam String nome, @RequestParam String especie,
                                          @RequestParam(required = false) String raca,
                                          @RequestParam(required = false) Integer idade,
                                          @RequestParam(required = false) Double peso,
                                          @RequestParam(required = false) String sexo,
                                          @RequestParam Long idTutor) {
        return Map.of("id_pet", repo.inserirPet(nome, especie, raca, idade, peso, sexo, idTutor));
    }

    // POST /api/procedures/pets/1/vacinas?vacina=V10&aplicacao=2026-10-01&proximaDose=2027-10-01
    @PostMapping("/pets/{idPet}/vacinas")
    public Map<String, Object> registrarVacina(@PathVariable Long idPet, @RequestParam String vacina,
                                               @RequestParam LocalDate aplicacao,
                                               @RequestParam(required = false) LocalDate proximaDose) {
        return Map.of("id_vacina", repo.registrarVacina(vacina, aplicacao, proximaDose, idPet));
    }

    // PUT /api/procedures/pets/1/peso?peso=33.0
    @PutMapping("/pets/{idPet}/peso")
    public void atualizarPeso(@PathVariable Long idPet, @RequestParam Double peso) {
        repo.atualizarPeso(idPet, peso);
    }

    // DELETE /api/procedures/pets/1
    @DeleteMapping("/pets/{idPet}")
    public void excluirPet(@PathVariable Long idPet) {
        repo.excluirPet(idPet);
    }

    // GET /api/procedures/pets
    @GetMapping("/pets")
    public List<Map<String, Object>> listarPets() {
        return repo.listarPets();
    }

    /**
     * Converte os erros ORA-200xx levantados pelo package em resposta HTTP 400
     * com a mensagem (assim o video mostra o tratamento de excecao chegando na API).
     */
    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> erroBanco(DataAccessException e) {
        String msg = String.valueOf(e.getMostSpecificCause().getMessage());
        // pega a primeira linha: "ORA-20003: Tutor informado nao existe."
        String primeiraLinha = msg.split("\n")[0];
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("erro", primeiraLinha));
    }
}
