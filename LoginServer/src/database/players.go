package database

import (
	"database/sql"
	"fmt"

	"github.com/opentibiabr/login-server/src/configs"
	"github.com/opentibiabr/login-server/src/grpc/login_proto_messages"
)

func LoadPlayers(db *sql.DB, acc *Account) ([]*login_proto_messages.Character, error) {
	var players []*login_proto_messages.Character

	// Consulta ajustada: removida a coluna 'lastlogin' para compatibilidade com o schema do Canary 3.4.1
	statement := fmt.Sprintf(
		`SELECT name, level, sex, vocation, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons 
		 FROM players 
		 WHERE account_id = "%d"`,
		acc.ID,
	)

	rows, err := db.Query(statement)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Obtém a lista de vocações uma única vez para evitar chamadas repetidas
	vocations := configs.GetServerVocations()

	for rows.Next() {
		player := login_proto_messages.Character{
			WorldId: 0,
			Info:    &login_proto_messages.CharacterInfo{},
			Outfit:  &login_proto_messages.CharacterOutfit{},
		}

		var vocation int

		// O número de argumentos no Scan agora corresponde exatamente às colunas selecionadas (10 colunas)
		err := rows.Scan(
			&player.Info.Name,
			&player.Info.Level,
			&player.Info.Sex,
			&vocation,
			&player.Outfit.LookType,
			&player.Outfit.LookHead,
			&player.Outfit.LookBody,
			&player.Outfit.LookLegs,
			&player.Outfit.LookFeet,
			&player.Outfit.Addons,
		)
		if err != nil {
			return nil, err
		}

		// Atribuição segura da vocação (evita pânico se o índice estiver fora do slice)
		if vocation >= 0 && vocation < len(vocations) {
			player.Info.Vocation = vocations[vocation]
		} else {
			player.Info.Vocation = "Desconhecida"
		}

		players = append(players, &player)
	}

	return players, nil
}
