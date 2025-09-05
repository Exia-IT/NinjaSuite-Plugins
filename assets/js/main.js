// Main JavaScript for NinjaSuite Plugins Repository
class PluginRepository {
    constructor() {
        this.baseUrl = window.location.origin + window.location.pathname.replace(/\/$/, '');
        this.repositoryData = null;
        this.pluginIndex = null;
        this.init();
    }

    async init() {
        try {
            await this.loadRepositoryData();
            await this.loadPluginIndex();
            this.updateStatistics();
            this.renderCategories();
            this.renderFeaturedPlugins();
        } catch (error) {
            console.error('Failed to initialize repository:', error);
            this.showError('Failed to load repository data');
        }
    }

    async loadRepositoryData() {
        try {
            const response = await fetch(`${this.baseUrl}/repository.json`);
            if (!response.ok) throw new Error('Failed to load repository data');
            this.repositoryData = await response.json();
        } catch (error) {
            console.error('Error loading repository data:', error);
            throw error;
        }
    }

    async loadPluginIndex() {
        try {
            const response = await fetch(`${this.baseUrl}/plugin-index.json`);
            if (!response.ok) throw new Error('Failed to load plugin index');
            this.pluginIndex = await response.json();
        } catch (error) {
            console.error('Error loading plugin index:', error);
            throw error;
        }
    }

    updateStatistics() {
        if (!this.repositoryData || !this.pluginIndex) return;

        const stats = this.repositoryData.statistics;
        
        document.getElementById('plugin-count').textContent = stats.totalPlugins || 0;
        document.getElementById('download-count').textContent = this.formatNumber(stats.totalDownloads || 0);
        document.getElementById('rating-average').textContent = (stats.averageRating || 0).toFixed(1);
    }

    renderCategories() {
        if (!this.repositoryData) return;

        const grid = document.getElementById('categories-grid');
        grid.innerHTML = '';

        this.repositoryData.categories.forEach(category => {
            const card = this.createCategoryCard(category);
            grid.appendChild(card);
        });
    }

    createCategoryCard(category) {
        const card = document.createElement('div');
        card.className = 'category-card';
        card.innerHTML = `
            <div class="category-icon">${category.icon}</div>
            <h3>${category.name}</h3>
            <p>${category.description}</p>
            <div class="category-count">${category.pluginCount} plugins</div>
        `;
        
        card.addEventListener('click', () => {
            window.location.href = `#category-${category.id}`;
        });

        return card;
    }

    renderFeaturedPlugins() {
        if (!this.pluginIndex) return;

        const grid = document.getElementById('featured-plugins');
        grid.innerHTML = '';

        if (this.pluginIndex.featured.length === 0) {
            grid.innerHTML = '<p style="text-align: center; color: #666;">No featured plugins available yet. Check back soon!</p>';
            return;
        }

        this.pluginIndex.featured.forEach(plugin => {
            const card = this.createPluginCard(plugin);
            grid.appendChild(card);
        });
    }

    createPluginCard(plugin) {
        const card = document.createElement('div');
        card.className = 'plugin-card';
        card.innerHTML = `
            <div class="plugin-header">
                <h4>${plugin.name}</h4>
                <span class="plugin-version">v${plugin.version}</span>
            </div>
            <p class="plugin-description">${plugin.description}</p>
            <div class="plugin-meta">
                <span class="plugin-category">${plugin.category}</span>
                <span class="plugin-rating">⭐ ${plugin.rating || 'N/A'}</span>
            </div>
            <div class="plugin-actions">
                <button class="btn btn-primary btn-small" onclick="installPlugin('${plugin.id}')">Install</button>
                <a href="plugins/${plugin.category}/${plugin.id}/" class="btn btn-secondary btn-small">Details</a>
            </div>
        `;
        return card;
    }

    formatNumber(num) {
        if (num >= 1000000) {
            return (num / 1000000).toFixed(1) + 'M';
        } else if (num >= 1000) {
            return (num / 1000).toFixed(1) + 'K';
        }
        return num.toString();
    }

    showError(message) {
        const errorDiv = document.createElement('div');
        errorDiv.className = 'error-message';
        errorDiv.style.cssText = `
            background: #f8d7da;
            color: #721c24;
            padding: 1rem;
            border-radius: 4px;
            margin: 1rem;
            border: 1px solid #f5c6cb;
        `;
        errorDiv.textContent = message;
        document.body.insertBefore(errorDiv, document.body.firstChild);
    }
}

// Global functions for plugin interactions
function installPlugin(pluginId) {
    alert(`Install functionality for plugin ${pluginId} will be implemented in NinjaSuite integration.`);
}

// Initialize repository when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new PluginRepository();
});

// Smooth scrolling for navigation links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});