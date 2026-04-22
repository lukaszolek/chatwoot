import { frontendURL } from '../../../helper/URLHelper';
import OutreachIndex from './pages/OutreachIndex.vue';
import OutreachPhotographers from './pages/OutreachPhotographers.vue';
import OutreachCampaigns from './pages/OutreachCampaigns.vue';
import OutreachDrafts from './pages/OutreachDrafts.vue';

const commonMeta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/outreach'),
    component: OutreachIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'outreach_dashboard_index',
        redirect: { name: 'outreach_photographers' },
        meta: commonMeta,
      },
      {
        path: 'photographers',
        name: 'outreach_photographers',
        component: OutreachPhotographers,
        meta: commonMeta,
      },
      {
        path: 'campaigns',
        name: 'outreach_campaigns',
        component: OutreachCampaigns,
        meta: commonMeta,
      },
      {
        path: 'drafts',
        name: 'outreach_drafts',
        component: OutreachDrafts,
        meta: commonMeta,
      },
    ],
  },
];
