# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddFkIndexesToMetadataMatchReviews do
  use Ecto.Migration

  def change do
    create index(:metadata_match_reviews, [:book_id])
    create index(:metadata_match_reviews, [:series_id])
  end
end
