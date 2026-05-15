import { frontendURL } from '../../../helper/URLHelper';
import OutreachIndex from './pages/OutreachIndex.vue';
import OutreachInbox from './pages/OutreachInbox.vue';
import OutreachPhotographers from './pages/OutreachPhotographers.vue';
import OutreachPipeline from './pages/OutreachPipeline.vue';
import OutreachStats from './pages/OutreachStats.vue';
import OutreachCampaigns from './pages/OutreachCampaigns.vue';
import OutreachKnowledge from './pages/OutreachKnowledge.vue';
import OutreachLearnings from './pages/OutreachLearnings.vue';

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
        redirect: { name: 'outreach_inbox' },
        meta: commonMeta,
      },
      {
        path: 'inbox',
        name: 'outreach_inbox',
        component: OutreachInbox,
        meta: commonMeta,
      },
      {
        path: 'photographers',
        name: 'outreach_photographers',
        component: OutreachPhotographers,
        meta: commonMeta,
      },
      {
        path: 'pipeline',
        name: 'outreach_pipeline',
        component: OutreachPipeline,
        meta: commonMeta,
      },
      {
        path: 'stats',
        name: 'outreach_stats',
        component: OutreachStats,
        meta: commonMeta,
      },
      {
        path: 'campaigns',
        name: 'outreach_campaigns',
        component: OutreachCampaigns,
        meta: commonMeta,
      },
      {
        path: 'knowledge',
        name: 'outreach_knowledge',
        component: OutreachKnowledge,
        meta: commonMeta,
      },
      {
        path: 'learnings',
        name: 'outreach_learnings',
        component: OutreachLearnings,
        meta: commonMeta,
      },
    ],
  },
];
