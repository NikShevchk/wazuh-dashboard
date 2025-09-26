/* eslint-disable @osd/eslint/require-license-header */
/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * The OpenSearch Contributors require contributions made to
 * this file be licensed under the Apache-2.0 license or a
 * compatible open source license.
 */

import { i18n } from '@osd/i18n';

export function translateDynamic(i18nKey: string, defaultMessage: string) {
  const t = i18n.translate;
  return t(i18nKey, { defaultMessage });
}
